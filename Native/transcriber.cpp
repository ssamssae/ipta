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
    if (argc != 2) return 2;
#ifdef _WIN32
    ggml_backend_load_all();
#endif
    auto cp = whisper_context_default_params();
    auto * ctx = whisper_init_from_file_with_params(argv[1], cp);
    if (!ctx) return 3;
    std::cout << "{\"ready\":true}" << std::endl;
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
    whisper_free(ctx);
    return 0;
}
