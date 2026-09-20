# 입타 윈도우

Windows 10/11 x64용 한국어 받아 적기 앱입니다. 받아 적기는 이 컴퓨터에서 처리합니다.

## 설치와 사용
1. [GitHub Releases](https://github.com/ssamssae/ipta/releases/latest)에서 `Ipta-0.1.21-windows.exe`를 받습니다. Python이나 whisper를 따로 설치하지 않습니다.
2. EXE를 실행하고 **지금 받기**로 받아 적기 모델(약 465MB)을 받습니다.
3. 마이크를 고르고 **Alt+D**로 녹음 시작/정지합니다. **Alt+Shift+C**로 취소합니다.
4. 결과는 쓰던 입력칸에 붙여 넣습니다. 입력되지 않으면 창의 **복사**를 사용하세요.
5. 다듬기는 선택입니다. LM Studio 로컬 모델, 또는 그록·커서·클로드·코덱스 CLI를 설치하고 본인 계정으로 로그인해 사용합니다. 요금과 이용 한도는 연결한 계정을 따릅니다.

WSL에 해당 CLI가 있으면 그곳의 로그인 계정을 우선 사용합니다. Cursor 데스크톱 앱과 `agent` CLI는 별개입니다. WSL에 CLI가 없으면 Windows 설치본을 찾습니다.

Windows EXE는 코드 서명되지 않았습니다. GitHub 배포 파일의 SHA-256을 확인할 수 있습니다. Mac 전용 기본 다듬기는 Windows에 없습니다.

## 데이터와 제거
설정·모델·로그는 `%APPDATA%\Ipta`에 저장합니다. EXE를 지우면 앱이 제거됩니다. 저장 데이터는 별도로 남습니다. 다듬기를 연결할 때만 글을 선택한 제공자로 보냅니다.

## 개발과 빌드
Python 3.12 환경에서 `pip install -r requirements-windows.txt`, `python -m ipta_win`으로 실행합니다. `Helpers`에 whisper.cpp v1.7.5의 `whisper-cli.exe`와 DLL을 둡니다.

`powershell -File scripts/build_windows.ps1`은 EXE를 만들고 패키지 자체 검사를 실행합니다. GitHub Actions도 같은 스크립트로 빌드합니다. 논리 검사는 `bash windows/scripts/test_windows.sh`로 실행합니다.

WSL 실제 계정의 그록·코덱스·커서 응답을 확인했습니다. 모든 앱/입력칸의 음성 입력 호환성이 검증된 것은 아닙니다. 클로드 실측은 유료 계정 부재로 제외했습니다.
