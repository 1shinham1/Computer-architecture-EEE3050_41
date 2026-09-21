# Lab1 macOS 실행 안내

Lab8과 같은 방식으로 컴파일할 파일을 직접 나열한 간단한 Makefile입니다.
Makefile은 `src/` 폴더 바로 바깥에 두세요.

```text
lab1_macos/
├── Makefile
├── README_KO.md
└── src/
    ├── ALU_Template.v
    └── ALU_TB.v
```

## 설치 및 실행

Homebrew가 설치된 macOS 터미널에서 실행합니다.
`make`가 없다면 `xcode-select --install`로 Command Line Tools를 먼저 설치하세요.

```sh
brew install icarus-verilog
cd ~/Downloads/lab1_macos  # 실제 압축을 푼 위치로 이동
make run_alu
```

- `make` 또는 `make run_alu`: 컴파일 후 시뮬레이션 실행
- `make build_alu`: 컴파일만 실행
- `make wave_alu`: 시뮬레이션 후 GTKWave로 파형 열기(GTKWave 별도 설치 필요)
- `make clean`: 생성된 실행 파일과 VCD 삭제

파형은 `vcd/ALU_TB.vcd`에 저장됩니다. 이를 위해 배포본의 `ALU_TB.v` initial 블록에
아래 두 줄만 추가했습니다. ALU 템플릿과 테스트 내용은 그대로입니다.
Makefile만 따로 가져가는 경우에는 기존 테스트벤치에도 아래 두 줄을 추가하세요.

```verilog
$dumpfile("vcd/ALU_TB.vcd");
$dumpvars(0, ALU_TB);
```

GTKWave 설치는 [공식 macOS 안내](https://gtkwave.github.io/gtkwave/install/mac.html)를 따르세요.
앱으로 설치했다면 시뮬레이션 실행 후 `open -a gtkwave vcd/ALU_TB.vcd`로 열 수도 있습니다.
GTKWave 없이도 텍스트 결과 확인과 VCD 생성은 가능합니다.

다음 Lab에서는 컴파일 명령에 필요한 `.v` 파일을 직접 추가하고, `-s ALU_TB`를
해당 테스트벤치의 모듈명으로 바꾸면 됩니다.
