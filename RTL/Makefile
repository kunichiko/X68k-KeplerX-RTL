#!/usr/bin/make -f

## プロジェクトの設定

# ライブラリの名前。デフォルトはwork
LIBRARYNAME = work
# テストベンチの一覧。entityの名前を指定する
# 後述のtestターゲットも参照
TESTBENCHES = X68KeplerX OPM_JT51
# ソースファイルの一覧は別のファイルに分けて記述 (SOURCES変数)
# (work-obj93.cfに変更を反映するため)
include sources.mk

## コンパイラの設定

# ghdlコマンドの名前
GHDLC = ghdl
# ghdlのオプション (全般)
# --work=NAME   : このプロジェクトのライブラリ名を指定する (デフォルト=work)
# --std         : 言語のバージョンを指定する。
#   --std=87        ... VHDL-87を使用する。
#   --std=93        ... VHDL-93を使用する。
#   --std=93c       ... おおよそVHDL-93だが、少し制限が緩い。(デフォルト)
#   --std=00        ... VHDL-2000を使用する。
#   --std=02        ... VHDL-2002を使用する。
# --ieee        : 標準ライブラリへの準拠の程度を指定する。
#   --ieee=none     ... 標準ライブラリすら使わない。
#   --ieee=standard ... 標準ライブラリを使うが、非標準ライブラリは使わない。
#   --ieee=synopsys ... 標準ライブラリに加えて、std_logic_arith,
#                       std_logic_signed, std_logic_unsigned,
#                       std_logic_textioの4つの非標準ライブラリを使う。
#   --ieee=mentor   ... 標準ライブラリに加えて、std_logic_arithを使う。
# -fexplicit    : 非標準ライブラリの有名なバグに対処する
# --mb-comments : コメント中で日本語等を使えるようにする
GHDLFLAGS = \
	-fexplicit --ieee=synopsys --work=$(LIBRARYNAME) \
	--mb-comments
# シミュレーションのオプション
# --assert-level   : シミュレーションが例外で停止する条件を指定する
#   --assert-level=none    ... いかなるassert/report文でも停止しない。
#   --assert-level=failure ... failure以上で停止。 (デフォルト)
#   --assert-level=error   ... error以上で停止。
#   --assert-level=warning ... warning以上で停止。
#   --assert-level=note    ... note以上で停止。
# --stop-time=TIME : シミュレーションが時間で停止する条件を指定する
# --vcd=FILENAME   : 波形(.vcd)を出力するときに用いる
# --wave=FILENAME  : 波形(.ghw)を出力するときに用いる
GHDL_SIM_OPT = --stop-time=1ms

# 疑似ターゲット (実際にはファイルを生成しないターゲット)
.PHONY: all test clean check-syntax

# デフォルトターゲット : 各テストベンチを生成
#all: $(TESTBENCHES)
all: check-syntax

# 各テストベンチの生成 : 実際にはghdlのビルドコマンドに委任
$(TESTBENCHES): work-obj93.cf $(SOURCES)
	$(GHDLC) -m $(GHDLFLAGS) $@

# テストの実行。必要に応じて変える
# --stop-time=1ms ... シミュレーション時間で1msnに達したら終了
# --vcd=hoge.vcd  ... VCD波形ファイルをhoge.vcdに出力
# --wave=hoge.ghw ... GHW波形ファイルをhoge.ghwに出力
# 波形を見るときはgtkwaveを使う
test: $(TESTBENCHES)
	$(GHDLC) -r $(GHDLFLAGS) hello
	$(GHDLC) -r $(GHDLFLAGS) sample_tb \
		--stop-time=1ms --vcd=sample.vcd --wave=sample.ghw

# ghdlが保持しているファイル一覧の更新
work-obj93.cf: sources.mk
	$(RM) $@
	(for i in $(SOURCES); do \
		$(GHDLC) -i $(GHDLFLAGS) $$i; \
	done) || ($(RM) $@; exit 1)

# flymake用 (文法チェック)
check-syntax:
	$(GHDLC) -s $(GHDLFLAGS) $(SOURCES)

# お掃除もghdlに任せる
clean :
	$(GHDLC) --clean
	$(RM) *.vcd *.ghw
