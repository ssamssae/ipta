# Private macOS transcription worker

The app starts `ipta-transcriber <model>` after recording starts. The worker loads
our existing pinned whisper.cpp model once, and keeps it for subsequent recordings.
Audio is still transcribed as a complete utterance; polishing and target-locked
insertion are unchanged. No network listener or new model is involved.

The private pipe protocol is newline-delimited JSON. The worker emits
`{"ready":true}`, accepts `{"wav":"/absolute/path.wav"}`, and replies with
`{"text":"..."}` or an error. Transcripts never go to diagnostic logs. Decoding
matches the existing Korean CLI arguments and clears prior utterance context.
EOF, cancellation, or application quit releases the worker. The Swift client also
releases it after 90 idle seconds, bounds each operation to 180 seconds, and falls
back to the original CLI when a worker is absent, crashes, or returns invalid data.

Build with `IPTA_ARCH=universal Scripts/build.sh` (or arm64/x86_64).
Run `python3 Scripts/test_warm_transcriber.py` for lifecycle/fallback regression.
Benchmark with the same model, threads and synthetic WAVs against the bundled
`whisper-cli -m MODEL -f WAV -l ko -nt -np -t 4`. Record startup separately, wait for
ready before measuring warm inference, and compare text as well as time. Initial
OS/Metal compilation is not representative of recurring latency. GPU decoding can
vary in number formatting, so text equality and semantic accuracy are separate
checks. This optimization does not shorten downstream AI polishing.
