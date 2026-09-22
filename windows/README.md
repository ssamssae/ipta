# 입타 윈도우

Windows 10/11 x64용 한국어 받아 적기 앱입니다. 받아 적기는 이 컴퓨터에서 처리합니다.

## 설치와 사용
1. [GitHub Releases](https://github.com/ssamssae/ipta/releases/latest)에서 `Ipta-0.1.21-windows.exe`를 받습니다. Python이나 whisper를 따로 설치하지 않습니다.
2. 아래 **실행 차단 안내**를 확인한 뒤 EXE를 실행합니다. 첫 실행 안내에서 **확인 · 시작하기**를 누르고 **지금 받기**로 모델을 받습니다.
3. 마이크를 고르고 **Alt+D**로 녹음 시작/정지합니다. **Alt+Shift+C**로 취소합니다.
4. 결과는 쓰던 입력칸에 붙여 넣습니다. 입력되지 않으면 창의 **복사**를 사용하세요.
5. 다듬기는 선택입니다. LM Studio 로컬 모델, 또는 그록·커서·클로드·코덱스 CLI를 설치하고 본인 계정으로 로그인해 사용합니다. 요금과 이용 한도는 연결한 계정을 따릅니다.

WSL에 해당 CLI가 있으면 그곳의 로그인 계정을 우선 사용합니다. Cursor 데스크톱 앱과 `agent` CLI는 별개입니다. WSL에 CLI가 없으면 Windows 설치본을 찾습니다.

Windows EXE는 코드 서명되지 않았습니다. GitHub 배포 파일의 SHA-256을 확인할 수 있습니다. Mac 전용 기본 다듬기는 Windows에 없습니다.

## 실행 차단 안내 (SmartScreen / 미서명)

Windows 10/11 **x64**용이며 코드 서명이 없습니다. 실행 전에는 [별도 시작 안내](Windows-start-guide.html)를 읽을 수 있습니다. 빌드 산출물에도 `Windows-start-guide.html`이 EXE와 함께 들어갑니다. 앱이 이미 차단된 상태에서는 앱 안의 안내 창을 띄울 수 없습니다.

1. 공식 `ssamssae/ipta` Releases에서 EXE와 **같은 버전**의 `.exe.sha256`을 받습니다.
2. PowerShell에서 `Get-FileHash .\Ipta-VERSION-windows.exe -Algorithm SHA256`을 실행해 배포 해시와 비교합니다. `VERSION`은 받은 버전으로 바꿉니다. 다르면 실행하지 말고 다시 받으세요. 해시는 파일 일치를 확인하며 서명·안전성 보증을 대신하지 않습니다.
3. **Windows의 PC 보호**가 뜨면 출처를 확인하고 신뢰하는 경우에만 **추가 정보 → 실행**을 선택합니다.
4. 실행 버튼이 없거나 Windows 11 Smart App Control·조직 정책이 차단하면 관리자에게 문의하세요. 보안 기능을 끄거나 앱이 차단을 자동 해제하는 방식은 제공하지 않습니다.

[Microsoft의 SmartScreen 설명](https://learn.microsoft.com/en-us/windows/apps/package-and-deploy/smartscreen-reputation) · [Smart App Control 설명](https://support.microsoft.com/en-us/windows/security/threat-malware-protection/smart-app-control-frequently-asked-questions)

첫 실행 안내는 확인 버튼을 누르면 저장되며, 메인 창의 **시작 안내**에서 다시 열 수 있습니다.

## 모델 다운로드와 오프라인 사용

- 처음 한 번 인터넷 연결과 약 **465 MiB**(487,601,967바이트, 약 488 MB)의 여유 공간이 필요합니다. 모델 교체 시에는 기존 파일과 임시 파일을 함께 저장할 공간도 필요합니다.
- **지금 받기**를 누르면 진행률·받은 용량이 표시됩니다. **100%** 이후 SHA-256 무결성 확인이 끝나야 녹음할 수 있습니다.
- 연결 실패·시간 초과·저장 실패 시 **다시 받기**가 표시됩니다. 인터넷·저장 공간·폴더 권한을 확인하고 재시도하세요. 이어받기 없이 처음부터 받으며, 실패한 파일을 준비 완료로 쓰지 않습니다.
- 다운로드 중에는 녹음을 시작하지 않습니다. 연결 응답 대기는 최대 30초이며, 다운로드 전체 시간은 연결 속도에 따라 달라집니다.
- 모델은 `%APPDATA%\Ipta\Models\ggml-small.bin`에 저장됩니다. 준비된 모델로는 **오프라인 받아 적기**가 가능하며, 첫 다운로드 전 오프라인에서는 사용할 수 없습니다. 온라인 제공자의 다듬기에는 별도 인터넷 연결이 필요합니다.

## 데이터와 제거
설정·모델·로그는 `%APPDATA%\Ipta`에 저장합니다. EXE를 지우면 앱이 제거됩니다. 저장 데이터는 별도로 남습니다. 다듬기를 연결할 때만 글을 선택한 제공자로 보냅니다.

## 개발과 빌드
Python 3.12 환경에서 `pip install -r requirements-windows.txt`, `python -m ipta_win`으로 실행합니다. `Helpers`에 whisper.cpp v1.7.5의 `whisper-cli.exe`와 DLL을 둡니다.

`powershell -File scripts/build_windows.ps1`은 EXE를 만들고 패키지 자체 검사를 실행합니다. GitHub Actions도 같은 스크립트로 빌드합니다. 논리 검사는 `bash windows/scripts/test_windows.sh`로 실행합니다.

WSL 실제 계정의 그록·코덱스·커서 응답을 확인했습니다. 모든 앱/입력칸의 음성 입력 호환성이 검증된 것은 아닙니다. 클로드 실측은 유료 계정 부재로 제외했습니다.
