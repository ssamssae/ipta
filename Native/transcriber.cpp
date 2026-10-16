#include "whisper.h"
#ifdef _WIN32
#include "ggml-backend.h"
#endif
#include "common-whisper.h"
#include "json.hpp"
#include <iostream>
#include <string>
#include <vector>

// Private stdin/stdout protocol: no listening socket, credentials or transcript logs.
// EOF releases the model when the owning app exits. Each request has fresh context.
int main(int argc, char ** argv) {
#ifdef _WIN32
    if (argc != 2 && argc != 3) return 2;
#else
    if (argc != 2) return 2;
#endif
#ifdef _WIN32
    ggml_backend_load_all();
#endif
    auto cp = whisper_context_default_params();
    auto * ctx = whisper_init_from_file_with_params(argv[1], cp);
    if (!ctx) return 3;
#ifdef _WIN32
    whisper_vad_context * vad = nullptr;
    if (argc == 3) {
        auto vp = whisper_vad_default_context_params();
        vp.n_threads = 2;
        vp.use_gpu = false;
        vad = whisper_vad_init_from_file_with_params(argv[2], vp);
        if (!vad) { whisper_free(ctx); return 4; }
    }
    std::cout << nlohmann::json({{"ready", true}, {"vad", vad != nullptr}}).dump() << std::endl;
#else
    std::cout << "{\"ready\":true}" << std::endl;
#endif
    std::string line;
    while (std::getline(std::cin, line)) {
        try {
            auto request = nlohmann::json::parse(line);
            std::vector<float> pcm;
            std::vector<std::vector<float>> channels;
            if (!read_audio_data(request.at("wav").get<std::string>(), pcm, channels, false)) {
                std::cout << "{\"error\":\"audio_read\"}" << std::endl;
                continue;
            }
#ifdef _WIN32
            if (vad) {
                auto vp = whisper_vad_default_params();
                // Keep short answers; only gate the request, never trim spoken audio.
                vp.min_speech_duration_ms = 100;
                auto * segments = whisper_vad_segments_from_samples(vad, vp, pcm.data(), int(pcm.size()));
                if (!segments) {
                    std::cout << "{\"error\":\"voice_detection\"}" << std::endl;
                    continue;
                }
                const bool speech = whisper_vad_segments_n_segments(segments) > 0;
                whisper_vad_free_segments(segments);
                if (!speech) {
                    // Do not reuse the preceding request's Whisper segments on silence.
                    std::cout << "{\"text\":\"\"}" << std::endl;
                    continue;
                }
            }
#endif
            // Match whisper-cli -l ko -nt -np -t 4, including its default beam size.
            auto p = whisper_full_default_params(WHISPER_SAMPLING_GREEDY);
            p.strategy = WHISPER_SAMPLING_BEAM_SEARCH;
            p.beam_search.beam_size = 5;
            p.language = "ko";
            p.n_threads = 4;
            p.no_context = true;
            p.no_timestamps = true;
            p.print_realtime = false;
            p.print_progress = false;
            p.print_timestamps = false;
            p.print_special = false;
            if (whisper_full(ctx, p, pcm.data(), int(pcm.size())) != 0) {
                std::cout << "{\"error\":\"inference\"}" << std::endl;
                continue;
            }
            std::string text;
            for (int i = 0; i < whisper_full_n_segments(ctx); ++i) {
                if (i) text += '\n';
                text += whisper_full_get_segment_text(ctx, i);
            }
            std::cout << nlohmann::json({{"text", text}}).dump() << std::endl;
        } catch (...) {
            std::cout << "{\"error\":\"request\"}" << std::endl;
        }
    }
#ifdef _WIN32
    whisper_vad_free(vad);
#endif
    whisper_free(ctx);
    return 0;
}
