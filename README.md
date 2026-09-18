# 입타 (Ipta)

맥에서만 한국어를 받아 적는 메뉴바 앱입니다. 말한 소리는 이 맥을 떠나지 않습니다. 파이썬, 홈브루, 위스퍼를 따로 설치할 필요는 없습니다.

**지원:** macOS 14 이상, Apple Silicon (arm64). Intel Mac은 아직 없습니다.

**받기:** [Releases](https://github.com/ssamssae/ipta/releases)에서 `Ipta-0.1.3-arm64.dmg`를 받습니다. 디스크를 열고 입타를 응용 프로그램 폴더로 끌어다 넣으면 됩니다.

**서명:** Minus Beta Studio 개발자 서명과 애플 공증이 되어 있습니다. Apple Silicon 맥 전용입니다.

## 쓰는 법
1. 입타를 응용 프로그램 폴더로 복사하거나 DMG에서 실행합니다.
2. 메뉴바 파형 아이콘 또는 열린 창에서 **녹음**. 처음이면 마이크 권한을 **입타**에 허용합니다.
3. 기본 단축키는 **Option-D** 시작/정지, **Option-Shift-C** 취소입니다. 다른 앱과 겹치면 창에 실패가 보이고, 설정에서 바꿀 수 있습니다. 상한 60초.
4. 무선 마이크 송신기 버튼도 설정에서 연결할 수 있습니다.
5. 단축키로 시작하면 그때의 앱·창·입력칸을 기억합니다. 정지면 같은 칸에만 넣습니다. 다른 앱/칸으로 옮겼으면 넣지 않고 결과에 남겨 **복사**합니다. 입타 자기 창에는 넣지 않습니다.
6. 받아 적기는 이 Mac에서만 합니다. 준비 파일(약 465MB)이 없으면 공식 주소에서 받고 크기·SHA-256을 검사합니다.
7. 말한 글을 다듬는 기능은 선택입니다. 연결을 켜면 본인 로그인이나 본인 키만 씁니다.

## 제거
앱을 삭제합니다. 모델·로그: `~/Library/Application Support/Malgyeol/`.

## 빌드 (개발자)
```bash
bash Scripts/build.sh
bash Scripts/check_rpath.sh dist/Malgyeol.app
bash Scripts/package_dmg.sh
```

## 라이선스
앱 소스 MIT. 엔진 whisper.cpp MIT. 모델은 OpenAI Whisper 가중치(MIT)의 ggml 변환본입니다. `THIRD_PARTY_NOTICES.md`.
