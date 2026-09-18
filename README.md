# 입타 (Ipta)

맥에서만 한국어를 받아 적는 메뉴바 앱입니다. 말한 소리는 이 맥을 떠나지 않습니다. 파이썬, 홈브루, 위스퍼를 따로 설치할 필요는 없습니다.

**지원:** macOS 14 이상, Apple Silicon (arm64). Intel Mac은 아직 없습니다.

**받기:** 다른 사람이 바로 설치할 파일은 아직 없습니다. 나중에 이 창고의 [Releases](https://github.com/ssamssae/ipta/releases)에 올립니다. 지금은 소스만 공개합니다.

**서명:** 아직 애플 공증이 아닙니다. 공증 전에 받은 앱은 다른 맥에서 막힐 수 있습니다.

## 쓰는 법
1. 입타를 응용 프로그램 폴더로 복사합니다.
2. 메뉴바 파형 아이콘 또는 열린 창에서 **녹음**. 처음이면 마이크를 입타에 허용합니다.
3. 기본 단축키는 **Option-D** 시작/정지, **Option-Shift-C** 취소입니다. 설정에서 바꿀 수 있습니다. 상한 60초.
4. 무선 마이크 송신기 버튼도 설정에서 연결할 수 있습니다. 한 번 누르면 녹음, 다시 누르면 받아 적어 넣습니다.
5. 단축키로 시작하면 그때의 입력칸을 기억합니다. 정지면 같은 칸에만 넣습니다.
6. 받아 적기는 이 맥에서만 합니다. 준비 파일(약 465MB)이 없으면 공식 주소에서 받고 크기와 해시를 검사합니다.
7. 말한 글을 다듬는 기능은 선택입니다. 무료는 이 맥에서만 정리하고, 연결을 켜면 본인 로그인이나 본인 키만 씁니다. 입타가 공용 키를 넣지 않습니다.

## 제거
앱을 삭제합니다. 모델과 로그: `~/Library/Application Support/Malgyeol/`.

## 빌드
```bash
bash Scripts/build.sh
bash Scripts/check_rpath.sh dist/Malgyeol.app
bash Scripts/package_dmg.sh
```

지금은 빌드 산출 파일 이름이 아직 `Malgyeol.app`입니다. 화면에 보이는 이름은 입타로 바꾸는 중입니다.

## 라이선스
앱 소스 MIT. 엔진 whisper.cpp MIT. 모델은 OpenAI Whisper 가중치(MIT)의 ggml 변환본입니다. `THIRD_PARTY_NOTICES.md`.
