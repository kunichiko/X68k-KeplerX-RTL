library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.std_logic_unsigned.all;

entity em3802 is
	generic (
		sysclk : integer := 100000;
		oscm : integer := 1000; -- 1MHz
		oscf : integer := 614; -- 614.4kHz
		rstlen : integer := 32
	);
	port (
		sys_clk : in std_logic;
		sys_rstn : in std_logic;
		req : in std_logic;
		ack : out std_logic;

		rw : in std_logic;
		addr : in std_logic_vector(2 downto 0);
		idata : in std_logic_vector(7 downto 0);
		odata : out std_logic_vector(7 downto 0);

		irq_n : out std_logic;
		int_vec : out std_logic_vector(7 downto 0);
		-- ADDRIN : in std_logic_vector(2 downto 0);
		-- DATIN : in std_logic_vector(7 downto 0);
		-- DATOUT : out std_logic_vector(7 downto 0);
		-- DATWR : in std_logic;
		-- DATRD : in std_logic;
		-- INT : out std_logic;
		-- IVECT : out std_logic_vector(7 downto 0);

		RxD : in std_logic;
		TxD : out std_logic;
		RxF : in std_logic; -- FSK同期信号入力(CZ-6BM1)
		TxF : out std_logic; -- FSK同期信号出力(CZ-6BM1)
		SYNC : out std_logic;
		CLICK : out std_logic;
		GPOUT : out std_logic_vector(7 downto 0);
		GPIN : in std_logic_vector(7 downto 0);
		GPOE : out std_logic_vector(7 downto 0);

		-- flow control
		transmitting : out std_logic;
		suspend : in std_logic
	);
end em3802;

architecture rtl of em3802 is
	type state_t is(
	IDLE,
	WR_ACK,
	RD_ACK
	);
	signal state : state_t;

	signal ADDRIN : std_logic_vector(2 downto 0);
	signal DATIN : std_logic_vector(7 downto 0);
	signal DATOUT : std_logic_vector(7 downto 0);
	signal DATWR : std_logic;
	signal DATRD : std_logic;
	signal lastwr : std_logic_vector(7 downto 0);

	signal reggroup : std_logic_vector(3 downto 0);
	signal rstcount : integer range 0 to rstlen - 1;
	signal crsten : std_logic;
	signal crstn : std_logic;

	signal R05, R14, R25, R26, R27, R44, R45, R66 : std_logic_vector(7 downto 0);
	signal R00, R02, R16, R34, R36, R54, R64, R74, R96 : std_logic_vector(7 downto 0);
	signal intclr : std_logic_vector(7 downto 0);
	signal intclr_req : std_logic;
	signal inten : std_logic_vector(7 downto 0);
	signal intstatus : std_logic_vector(7 downto 0);
	signal intstatus_d : std_logic_vector(7 downto 0);
	signal intvectoff : std_logic_vector(2 downto 0);
	signal CT, OB, VE, VM : std_logic;
	signal ASE, MCE, CDE, MCDS : std_logic;
	signal MCFS : std_logic_vector(1 downto 0);
	signal rmsg_tx, rmsg_sync, rmsg_cc, rmsg_pc, rmsg_rc : std_logic;
	signal rmsg_content : std_logic_vector(2 downto 0);
	signal fifo_IRx : std_logic;
	signal rxrate : std_logic_vector(4 downto 0);
	signal rxsrc : std_logic;
	signal RxCL, RxPE, RxPL, RxEO, RxSL, RxST : std_logic;
	signal IDCL : std_logic;
	signal ID_MAKER : std_logic_vector(6 downto 0);
	signal BDRE : std_logic;
	signal ID_DEVICE : std_logic_vector(6 downto 0);
	signal RxC : std_logic;
	signal RxOVC : std_logic;
	signal FLTE : std_logic;
	signal BLKC : std_logic;
	signal RxOLC : std_logic;
	signal AHE : std_logic;
	signal RxE : std_logic;
	signal TxRx : std_logic;
	signal TxDF : std_logic;
	signal txrate : std_logic_vector(4 downto 0);
	signal TxCL, TxPE, TxPL, TxEO, TxSL, TxST : std_logic;
	signal TxC, BRKE, TxIDLC, TxE : std_logic;
	signal ME, CFC, DE, APD, PN, PDFC : std_logic;
	signal CLKM, OUTE : std_logic;
	signal CCLD : std_logic;
	signal CCLDVAL : std_logic_vector(6 downto 0);
	signal PCADD : std_logic;
	signal PCCLR : std_logic;
	signal INTRATE : std_logic_vector(3 downto 0);
	signal PCADDVAL : std_logic_vector(14 downto 0);
	signal GTLDVAL : std_logic_vector(13 downto 0);
	signal GTLD : std_logic;
	signal GT_COUNT : std_logic_vector(17 downto 0);
	signal GT_ZERO : std_logic;
	signal MTLDVAL : std_logic_vector(13 downto 0);
	signal MTLD : std_logic;

	signal txfifowdat : std_logic_vector(7 downto 0);
	signal txfifowr : std_logic;
	signal txfifordat : std_logic_vector(7 downto 0);
	signal txfiford : std_logic;
	signal txfifoclr : std_logic;
	signal txfifoemp : std_logic;
	signal txfifofull : std_logic;

	signal rxfifowdat : std_logic_vector(7 downto 0);
	signal rxfifowr : std_logic;
	signal rxfifordat : std_logic_vector(7 downto 0);
	signal rxfiford : std_logic;
	signal rxfifoclr : std_logic;
	signal rxfifoemp : std_logic;
	signal rxfifofull : std_logic;

	constant divm : integer := sysclk/oscm;
	constant divf : integer := sysclk/oscf;
	signal countm : integer range 0 to divm;
	signal countf : integer range 0 to divf;

	signal rxdivcount : integer range 0 to 2047;
	signal rxsft : std_logic;

	signal sftm : std_logic;
	signal sftf : std_logic;

	signal rxframelen : integer range 1 to 13;
	signal srxbit : std_logic;
	signal rxbyte : std_logic_vector(7 downto 0);
	signal rxdata : std_logic_vector(12 downto 0);
	signal rxdone : std_logic;
	signal rxstoperr : std_logic;
	signal rxparerr : std_logic;
	signal rxstop2err : std_logic;
	signal rxbusy : std_logic;

	signal txdivcount : integer range 0 to 2047;
	signal txsft : std_logic;
	signal txframelen : integer range 1 to 13;
	signal txdata : std_logic_vector(12 downto 0);
	signal txemp : std_logic;
	signal txwr : std_logic;
	signal txbusy : std_logic;
	signal rstcmd : std_logic;

	component datfifo
		generic (
			datwidth : integer := 8;
			depth : integer := 8
		);
		port (
			datin : in std_logic_vector(datwidth - 1 downto 0);
			datwr : in std_logic;

			datout : out std_logic_vector(datwidth - 1 downto 0);
			datrd : in std_logic;

			datnum : out integer range 0 to depth - 1;
			empty : out std_logic;
			full : out std_logic;

			clr : in std_logic;

			clk : in std_logic;
			rstn : in std_logic
		);
	end component;

	component rxframe
		generic (
			maxlen : integer := 8;
			maxwid : integer := 4
		);
		port (
			SD : in std_logic; -- serial data input

			SFT : in std_logic; -- shift enable signal
			WIDTH : in std_logic_vector(maxwid - 1 downto 0); -- 1bit width of serial
			LEN : in integer range 1 to maxlen;

			DATA : out std_logic_vector(maxlen - 1 downto 0); --received data
			DONE : out std_logic; -- received

			BUSY : out std_logic;
			STOPERR : out std_logic; -- stop error detect
			SFTRST : in std_logic; -- stop receive and reset

			clk : in std_logic; -- system clock
			rstn : in std_logic -- system reset
		);
	end component;

	component txframe
		generic (
			maxlen : integer := 8; --max bits/frame
			maxwid : integer := 4 --max bit/clock
		);
		port (
			SD : out std_logic; -- serial data output
			DRCNT : out std_logic; -- driver control signal
			SUSPEND : in std_logic; -- 送信を止めたい場合はSUSPENDを'1'にして、DRCNTが'0'になるのを待つ

			SFT : in std_logic; -- shift enable signal
			WIDTH : in std_logic_vector(maxwid - 1 downto 0); -- 1bit width of serial
			LEN : in integer range 1 to maxlen; --bits/frame
			STPLEN : in integer range 1 to 4; --stop bit length*2

			DATA : in std_logic_vector(maxlen - 1 downto 0); -- transmit data input
			WRITE : in std_logic; -- transmit write signal(start)
			BUFEMP : out std_logic; -- transmit buffer empty signal

			clk : in std_logic; -- system clock
			rstn : in std_logic -- system reset
		);
	end component;

begin

	transmitting <= txbusy;

	-- 割り込み処理
	-- R00 (Read only) : 割込ベクタ
	--  b7-5 : 割り込みベクタオフセット(R04で指定)
	--  b4-1 : 割込要因
	--    "1000" : アクティブな割込要因なし
	--    "0111" : General Timer (タイマのカウンタが0)
	--	  "0110" : FIFO-Tx empty (送信FIFOが空)
	--    "0101" : FIFO-Rx ready (受信FIFOにデータがある)
	--    "0100" : Off-line detected (300msec以内に受信なし)
	--    "0011" : Recording Counter (レコーディングカウンタが0になった)
	--    "0010" : Play-back Counter (プレイバックカウンタが負になった)
	--    "0001" : Click Counter (クリックカウンタが0になった) / MIDI-clock detected (FIFO-IRxの最古のデータが x"F8")
	--             (どちらで使うかはR05で選択)
	--    "0000" : MIDI real-time message detected (FIFO-IRxの最古のデータが x"F9" 〜 x"FD")
	--  b0   : 常に '0'
	process (sys_clk, sys_rstn)
	begin
		if (sys_rstn = '0') then
			irq_n <= '1';
			int_vec <= (others => '0');
			R00 <= "00010000";
			R02 <= (others => '0');
			intstatus <= (others => '0');
			intstatus_d <= (others => '0');
		elsif (sys_clk' event and sys_clk = '1') then
			-- 割込要因の判定
			intstatus_d <= intstatus;
			intstatus(7) <= GT_ZERO; -- General Timer
			intstatus(6) <= txfifoemp; -- FIFO-Tx empty
			intstatus(5) <= '0'; -- FIFO-Rx ready
			intstatus(4) <= '0'; -- Off-line detected
			intstatus(3) <= '0'; -- Recording Counter
			intstatus(2) <= '0'; -- Play-back Counter
			intstatus(1) <= '0'; -- Click Counter / MIDI-clock detected
			intstatus(0) <= '0'; -- MIDI real-time message detected

			-- 割込要因発生検出(rising edge)
			for i in 0 to 7 loop
				if (intstatus_d(i) = '0' and intstatus(i) = '1') then
					R02(i) <= '1';
				end if;
			end loop;

			-- 割込要求のクリア
			if (intclr_req = '1') then
				R02 <= R02 and (not intclr);
			end if;

			-- プライオリティエンコーダー
			R00(7 downto 5) <= intvectoff;
			if (R02(7) = '1' and inten(7) = '1') then
				R00(4 downto 1) <= "0" & "111";
			elsif (R02(6) = '1' and inten(6) = '1') then
				R00(4 downto 1) <= "0" & "110";
			elsif (R02(5) = '1' and inten(5) = '1') then
				R00(4 downto 1) <= "0" & "101";
			elsif (R02(4) = '1' and inten(4) = '1') then
				R00(4 downto 1) <= "0" & "100";
			elsif (R02(3) = '1' and inten(3) = '1') then
				R00(4 downto 1) <= "0" & "011";
			elsif (R02(2) = '1' and inten(2) = '1') then
				R00(4 downto 1) <= "0" & "010";
			elsif (R02(1) = '1' and inten(1) = '1') then
				R00(4 downto 1) <= "0" & "001";
			elsif (R02(0) = '1' and inten(0) = '1') then
				R00(4 downto 1) <= "0" & "000";
			else
				R00(4 downto 1) <= "1" & "000";
			end if;
			int_vec <= R00;

			--
			if (R00(4) = '0') then
				irq_n <= '0';
			else
				irq_n <= '1';
			end if;
		end if;
	end process;

	-- sysclk synchronized inputs
	process (sys_clk, sys_rstn)
	begin
		if (sys_rstn = '0') then
			state <= IDLE;
			DATIN <= (others => '0');
			ADDRIN <= (others => '0');
			--
			ack <= '0';
		elsif (sys_clk' event and sys_clk = '1') then
			ack <= '0';
			DATWR <= '0';
			DATRD <= '0';

			case state is
				when IDLE =>
					if req = '1' then
						ADDRIN <= addr;
						if rw = '0' then
							state <= WR_ACK;
							DATIN <= idata;
							DATWR <= '1';
							ack <= '1';
						else
							state <= RD_ACK;
							DATRD <= '1';
							ack <= '1';
						end if;
					end if;

					-- write cycle
				when WR_ACK =>
					if req = '1' then
						ack <= '1';
					else
						ack <= '0';
						state <= IDLE;
					end if;

					-- read cycle
				when RD_ACK =>
					if req = '1' then
						ack <= '1';
					else
						ack <= '0';
						state <= IDLE;
					end if;
				when others =>
					state <= IDLE;
			end case;
		end if;
	end process;
	odata <= DATOUT;

	-- 送信FIFO
	--
	-- SX-68M-IIでテストしたところ、YM3802の送信FIFOは16バイトのようだが、Kepler-Xでは多めにしておかないと
	-- 取りこぼすケースがあるので多めにしてある
	-- RCD.x をディスアセンブルしてみたところ、txfifo full を見ずに送っているように見えるところがあったので、
	-- 一部の曲を再生すると、ピッチベンドの送信が間に合わずに音程がずれることがあった
	-- YM3802の実機だと問題ない理由がわからないが、送信レートの挙動が違うなどして、Kepler-Xでは問題になるのかもしれない
	txfifo : datfifo generic map(
		8, 128) port map(
		datin => txfifowdat,
		datwr => txfifowr,

		datout => txfifordat,
		datrd => txfiford,

		datnum => open,
		empty => txfifoemp,
		full => txfifofull,

		clr => txfifoclr,

		clk => sys_clk,
		rstn => sys_rstn
	);

	-- 受信FIFO
	rxfifo : datfifo generic map(
		8, 128) port map(
		datin => rxfifowdat,
		datwr => rxfifowr,

		datout => rxfifordat,
		datrd => rxfiford,

		datnum => open,
		empty => rxfifoemp,
		full => rxfifofull,

		clr => rxfifoclr,

		clk => sys_clk,
		rstn => sys_rstn
	);

	process (sys_clk, sys_rstn)begin
		if (sys_rstn = '0') then
			rstcount <= rstlen - 1;
			rstcmd <= '0';
		elsif (sys_clk' event and sys_clk = '1') then
			if (crsten = '1') then
				if (rstcount > 0) then
					rstcount <= rstcount - 1;
					rstcmd <= '0';
				else
					rstcmd <= '1';
				end if;
			else
				rstcmd <= '0';
			end if;
		end if;
	end process;

	crstn <= sys_rstn and (not rstcmd);

	process (sys_clk, sys_rstn)
		variable ldatwr : std_logic;
	begin
		if (sys_rstn = '0') then
			reggroup <= (others => '0');
			crsten <= '0';
			intclr <= (others => '0');
			intclr_req <= '0';
			inten <= (others => '0');
			intvectoff <= (others => '0');
			R05 <= (others => '0');
			R14 <= (others => '0');
			R25 <= (others => '0');
			R26 <= (others => '0');
			R27 <= (others => '0');
			R44 <= (others => '0');
			R45 <= (others => '0');
			R66 <= (others => '0');
			rmsg_tx <= '0';
			rmsg_sync <= '0';
			rmsg_cc <= '0';
			rmsg_pc <= '0';
			rmsg_rc <= '0';
			rmsg_content <= (others => '0');
			fifo_IRx <= '0';
			rxrate <= (others => '0');
			rxsrc <= '0';
			RxC <= '0';
			RxOVC <= '0';
			FLTE <= '0';
			BLKC <= '0';
			RxOLC <= '0';
			AHE <= '0';
			RxE <= '0';
			TxC <= '0';
			BRKE <= '0';
			TxIDLC <= '0';
			TxE <= '0';
			txfifowdat <= (others => '0');
			txfifowr <= '0';
			ME <= '0';
			CFC <= '0';
			DE <= '0';
			APD <= '0';
			PN <= '0';
			PDFC <= '0';
			CCLD <= '0';
			CCLDVAL <= (others => '0');
			PCADD <= '0';
			PCCLR <= '0';
			INTRATE <= (others => '0');
			PCADDVAL <= (others => '0');
			GTLDVAL <= (others => '0');
			GTLD <= '0';
			GT_COUNT <= (others => '0');
			GT_ZERO <= '0';
			MTLDVAL <= (others => '0');
			MTLD <= '0';
			GPOE <= (others => '0');
			GPOUT <= (others => '0');
			ldatwr := '0';
		elsif (sys_clk' event and sys_clk = '1') then
			intclr <= (others => '0');
			intclr_req <= '0';
			rmsg_tx <= '0';
			rmsg_sync <= '0';
			rmsg_cc <= '0';
			rmsg_pc <= '0';
			rmsg_rc <= '0';
			fifo_IRx <= '0';
			RxC <= '0';
			RxOVC <= '0';
			BLKC <= '0';
			RxOLC <= '0';
			TxC <= '0';
			TxIDLC <= '0';
			txfifowr <= '0';
			CFC <= '0';
			PDFC <= '0';
			CCLD <= '0';
			PCADD <= '0';
			PCCLR <= '0';
			GTLD <= '0';
			MTLD <= '0';
			if (rstcmd = '1') then
				intclr <= (others => '0');
				intclr_req <= '0';
				inten <= (others => '0');
				intvectoff <= (others => '0');
				R05 <= (others => '0');
				R14 <= (others => '0');
				R25 <= (others => '0');
				R26 <= (others => '0');
				R27 <= (others => '0');
				R44 <= (others => '0');
				R45 <= (others => '0');
				R66 <= (others => '0');
				rmsg_tx <= '0';
				rmsg_sync <= '0';
				rmsg_cc <= '0';
				rmsg_pc <= '0';
				rmsg_rc <= '0';
				rmsg_content <= (others => '0');
				fifo_IRx <= '0';
				rxrate <= (others => '0');
				rxsrc <= '0';
				RxC <= '0';
				RxOVC <= '0';
				FLTE <= '0';
				BLKC <= '0';
				RxOLC <= '0';
				AHE <= '0';
				RxE <= '0';
				TxC <= '0';
				BRKE <= '0';
				TxIDLC <= '0';
				TxE <= '0';
				txfifowdat <= (others => '0');
				txfifowr <= '0';
				ME <= '0';
				CFC <= '0';
				DE <= '0';
				APD <= '0';
				PN <= '0';
				PDFC <= '0';
				CCLD <= '0';
				CCLDVAL <= (others => '0');
				PCADD <= '0';
				PCCLR <= '0';
				INTRATE <= (others => '0');
				PCADDVAL <= (others => '0');
				GTLDVAL <= (others => '0');
				GTLD <= '0';
				GT_COUNT <= (others => '0');
				GT_ZERO <= '0';
				MTLDVAL <= (others => '0');
				MTLD <= '0';
				GPOE <= (others => '0');
				GPOUT <= (others => '0');
			end if;
			-- General Purpose Counter
			if (sftm = '1') then
				GT_ZERO <= '0';
				if (GT_COUNT = 0) then
					GT_ZERO <= '1';
					--GT_COUNT <= GTLDVAL & "0000";
					GT_COUNT <= "0" & GTLDVAL & "000";
				else
					GT_COUNT <= GT_COUNT - 1;
				end if;
			end if;

			-- Register Write Cycle
			if (DATWR = '1' and ldatwr = '0') then
				lastwr <= DATIN; -- ライトオンリーレジスタを読むと最後に書いたものが読めるので残しておく
				case ADDRIN is
					when "001" => -- R01
						crsten <= DATIN(7);
						reggroup <= DATIN(3 downto 0);
					when "010" => -- R02
						null; -- read only

					when "011" => -- R03
						intclr <= DATIN;
						intclr_req <= '1';
					when "100" =>
						case reggroup is
							when x"0" => -- R04
								intvectoff <= DATIN(7 downto 5);
							when x"1" => -- R14
								R14 <= DATIN;
							when x"2" => -- R24
								rxsrc <= DATIN(5);
								rxrate <= DATIN(4 downto 0);
							when x"4" => -- R44
								R44 <= DATIN;
							when x"8" => -- R84
								GTLDVAL(7 downto 0) <= DATIN;
							when x"9" =>
								GPOE <= DATIN;
							when others =>
						end case;
					when "101" =>
						case reggroup is
							when x"0" => -- R05
								R05 <= DATIN;
							when x"1" => -- R15 MIDIリアルタイムメッセージ送信
								rmsg_content <= DATIN(2 downto 0);
								if (DATIN(2 downto 0) = "000") then
									rmsg_tx <= '1';
									rmsg_sync <= '1';
									rmsg_cc <= '1';
									rmsg_pc <= '1';
									rmsg_rc <= '1';
								else
									rmsg_tx <= DATIN(7);
									rmsg_sync <= DATIN(6);
									rmsg_cc <= DATIN(5);
									rmsg_pc <= DATIN(4);
									rmsg_rc <= DATIN(3);
								end if;
							when x"2" => -- R25
								R25 <= DATIN;
							when x"3" => -- R35
								RxC <= DATIN(7);
								RxOVC <= DATIN(6);
								FLTE <= DATIN(4);
								BLKC <= DATIN(3);
								RxOLC <= DATIN(2);
								AHE <= DATIN(1);
								RxE <= DATIN(0);
							when x"4" => -- R45
								R45 <= DATIN;
							when x"5" => -- R55
								TxC <= DATIN(7);
								BRKE <= DATIN(3);
								TxIDLC <= DATIN(2);
								TxE <= DATIN(0);
							when x"6" => -- R65
								ME <= DATIN(7);
								CFC <= DATIN(4);
								DE <= DATIN(3);
								APD <= DATIN(2);
								PN <= DATIN(1);
								PDFC <= DATIN(0);
							when x"7" => -- R75
								PCADD <= DATIN(5);
								PCCLR <= DATIN(4);
								INTRATE <= DATIN(3 downto 0);
							when x"8" => -- R85
								GTLDVAL(13 downto 8) <= DATIN(5 downto 0);
								GTLD <= DATIN(7);
								if (DATIN(7) = '1') then
									GT_COUNT <= DATIN(5 downto 0) & GTLDVAL(7 downto 0) & "0000";
								end if;
							when x"9" => -- R95
								GPOUT <= DATIN;
							when others =>
						end case;
					when "110" =>
						case reggroup is
							when x"0" => -- R06
								inten <= DATIN;
							when x"2" => -- R26
								R26 <= DATIN;
							when x"5" => -- R56
								txfifowdat <= DATIN;
								txfifowr <= '1';
							when x"6" => -- R66
								R66 <= DATIN;
							when x"7" => -- R76
								PCADDVAL(7 downto 0) <= DATIN;
							when x"8" => -- R86
								MTLDVAL(7 downto 0) <= DATIN;
							when others =>
						end case;
					when "111" =>
						case reggroup is
							when x"1" =>
								fifo_IRx <= DATIN(0);
							when x"2" =>
								R27 <= DATIN;
							when x"6" =>
								CCLD <= DATIN(7);
								CCLDVAL <= DATIN(6 downto 0);
							when x"7" =>
								PCADDVAL(14 downto 8) <= DATIN(6 downto 0);
							when x"8" =>
								MTLDVAL(13 downto 8) <= DATIN(5 downto 0);
								MTLD <= DATIN(7);
							when others =>
						end case;
					when others =>
				end case;
			end if;
			ldatwr := datwr;
		end if;
	end process;

	CT <= R05(3);
	OB <= R05(2);
	VE <= R05(1);
	VM <= R05(0);
	ASE <= R14(5);
	MCE <= R14(4);
	CDE <= R14(3);
	MCDS <= R14(2);
	MCFS <= R14(1 downto 0);
	RxCL <= R25(5);
	RxPE <= R25(4);
	RxPL <= R25(3);
	RxEO <= R25(2);
	RxSL <= R25(1);
	RxST <= R25(0);
	IDCL <= R26(7);
	ID_MAKER <= R26(6 downto 0);
	BDRE <= R27(7);
	ID_DEVICE <= R27(6 downto 0);
	TxRx <= R44(6);
	TxDF <= R44(5);
	txrate <= R44(4 downto 0);
	TxCL <= R45(5);
	TxPE <= R45(4);
	TxPL <= R45(3);
	TxEO <= R45(2);
	TxSL <= R45(1);
	TxST <= R45(0);
	CLKM <= R66(1);
	OUTE <= R66(0);

	DATOUT <= R00 when reggroup = x"0" and ADDRIN = "000" else
		R02 when reggroup = x"0" and ADDRIN = "010" else
		R16 when reggroup = x"1" and ADDRIN = "110" else
		R34 when reggroup = x"3" and ADDRIN = "100" else
		R36 when reggroup = x"3" and ADDRIN = "110" else
		R54 when reggroup = x"5" and ADDRIN = "100" else
		R64 when reggroup = x"6" and ADDRIN = "100" else
		R74 when reggroup = x"7" and ADDRIN = "100" else
		R96 when reggroup = x"9" and ADDRIN = "110" else
		lastwr; -- ライトオンリーレジスタを読み出すと最後に書いたものが読める

	R34(7) <= not rxfifoemp;
	rxfifoclr <= RxC;
	txfifoclr <= TxC;
	R36 <= rxfifordat;

	process (sys_clk, crstn)
		variable rd, lrd : std_logic;
	begin
		if (crstn = '0') then
			lrd := '0';
			rxfiford <= '0';
		elsif (sys_clk' event and sys_clk = '1') then
			rxfiford <= '0';
			if (DATWR = '1' and ADDRIN = "110" and reggroup = x"3") then
				rd := '1';
			else
				rd := '0';
			end if;
			if (rd = '0' and lrd = '1') then
				rxfiford <= '1';
			end if;
			lrd := rd;
		end if;
	end process;

	R54(7) <= txfifoemp;
	R54(6) <= not txfifofull;
	R54(5 downto 3) <= (others => '0');

	process (sys_clk, crstn)begin
		if (crstn = '0') then
			countm <= divm - 1;
			sftm <= '0';
		elsif (sys_clk' event and sys_clk = '1') then
			sftm <= '0';
			if (countm = 0) then
				sftm <= '1';
				countm <= divm - 1;
			else
				countm <= countm - 1;
			end if;
		end if;
	end process;

	process (sys_clk, crstn)begin
		if (crstn = '0') then
			countf <= divf - 1;
			sftf <= '0';
		elsif (sys_clk' event and sys_clk = '1') then
			sftf <= '0';
			if (countf = 0) then
				sftf <= '1';
				countf <= divf - 1;
			else
				countf <= countf - 1;
			end if;
		end if;
	end process;

	process (sys_clk, crstn)begin
		if (crstn = '0') then
			rxdivcount <= 0;
		elsif (sys_clk' event and sys_clk = '1') then
			rxsft <= '0';
			if (rxrate(4) = '0' and sftm = '1') then
				if (rxdivcount = 0) then
					rxsft <= '1';
					if (rxrate(3) = '0') then
						rxdivcount <= 3;
					else
						rxdivcount <= 7;
					end if;
				else
					rxdivcount <= rxdivcount - 1;
					if (rxrate(3) = '0') then
						if (rxdivcount > 3) then
							rxdivcount <= 3;
						end if;
					else
						if (rxdivcount > 7) then
							rxdivcount <= 7;
						end if;
					end if;
				end if;
			elsif (rxrate(4) = '1' and sftf = '1') then
				if (rxdivcount = 0) then
					rxsft <= '1';
					case rxrate(3 downto 0)is
						when x"8" =>
							rxdivcount <= 15;
						when x"9" =>
							rxdivcount <= 31;
						when x"a" =>
							rxdivcount <= 63;
						when x"b" =>
							rxdivcount <= 127;
						when x"c" =>
							rxdivcount <= 255;
						when x"d" =>
							rxdivcount <= 511;
						when x"e" =>
							rxdivcount <= 1023;
						when x"f" =>
							rxdivcount <= 2047;
						when others =>
							rxdivcount <= 7;
					end case;
				else
					rxdivcount <= rxdivcount - 1;
					case rxrate(3 downto 0) is
						when x"8" =>
							if (rxdivcount > 15) then
								rxdivcount <= 15;
							end if;
						when x"9" =>
							if (rxdivcount > 31) then
								rxdivcount <= 31;
							end if;
						when x"a" =>
							if (rxdivcount > 63) then
								rxdivcount <= 63;
							end if;
						when x"b" =>
							if (rxdivcount > 127) then
								rxdivcount <= 127;
							end if;
						when x"c" =>
							if (rxdivcount > 255) then
								rxdivcount <= 255;
							end if;
						when x"d" =>
							if (rxdivcount > 511) then
								rxdivcount <= 511;
							end if;
						when x"e" =>
							if (rxdivcount > 1023) then
								rxdivcount <= 1023;
							end if;
						when x"f" =>
						when others =>
							if (rxdivcount > 7) then
								rxdivcount <= 7;
							end if;
					end case;
				end if;
			end if;
		end if;
	end process;

	process (sys_clk, crstn)begin
		if (crstn = '0') then
			srxbit <= '1';
		elsif (sys_clk' event and sys_clk = '1') then
			if (RxE = '1') then
				srxbit <= RxD;
			else
				srxbit <= '1';
			end if;
		end if;
	end process;

	process (RxCL, RxPE, RxPL, RxSL)
		variable vlen : integer range 1 to 13;
	begin
		if (RxCL = '1') then
			vlen := 7;
		else
			vlen := 8;
		end if;
		if (RxPE = '1') then
			if (RxPL = '1') then
				vlen := vlen + 4;
			else
				vlen := vlen + 1;
			end if;
		end if;
		if (RxSL = '1') then
			vlen := vlen + 1;
		end if;
		rxframelen <= vlen;
	end process;

	rxunit : rxframe generic map(
		13, 3) port map(
		SD => srxbit,

		SFT => rxsft,
		WIDTH => "100",
		LEN => rxframelen,

		DATA => rxdata,
		DONE => rxdone,

		BUSY => rxbusy,
		STOPERR => rxstoperr,
		SFTRST => '0',

		clk => sys_clk,
		rstn => crstn
	);
	rxbyte <= rxdata(7 downto 0) when RxCL = '0' else ('0' & rxdata(6 downto 0));
	process (rxdone, RxCL, RxPE, RxPL, RxEO, RxSL, RxST)
		variable par : std_logic;
		variable par4 : std_logic_vector(3 downto 0);
		variable parloc : integer range 0 to 12;
		variable parlen : integer range 0 to 4;
	begin
		if (rxdone = '1') then
			par := '0';
			if (RxCL = '0') then
				for i in 0 to 7 loop
					par := par xor rxdata(i);
				end loop;
				par4 := rxdata(3 downto 0) xor rxdata(7 downto 4);
				parloc := 8;
			else
				for i in 0 to 6 loop
					par := par xor rxdata(i);
				end loop;
				par4 := rxdata(3 downto 0) xor ('0' & rxdata(6 downto 4));
				parloc := 7;
			end if;
			if (RxPE = '1') then
				if (RxPL = '0') then
					parlen := 1;
					if (RxEO = '0') then
						if (par = rxdata(parloc)) then
							rxparerr <= '0';
						else
							rxparerr <= '1';
						end if;
					else
						if (par = rxdata(parloc)) then
							rxparerr <= '1';
						else
							rxparerr <= '0';
						end if;
					end if;
				else
					parlen := 4;
					if (RxEO = '0') then
						if (par4 = rxdata(parloc + 3 downto parloc)) then
							rxparerr <= '0';
						else
							rxparerr <= '1';
						end if;
					else
						if ((par4 xor rxdata(parloc + 3 downto parloc)) = "0000") then
							rxparerr <= '0';
						else
							rxparerr <= '1';
						end if;
					end if;
				end if;
			else
				rxparerr <= '0';
				parlen := 0;
			end if;
			if (RxSL = '1') then
				if (RxST = '1') then
					if (rxdata(parloc + parlen) = '0') then
						rxstop2err <= '0';
					else
						rxstop2err <= '1';
					end if;
				else
					if (rxdata(parloc + parlen) = '0') then
						rxstop2err <= '1';
					else
						rxstop2err <= '0';
					end if;
				end if;
			else
				rxstop2err <= '0';
			end if;
		end if;
	end process;

	rxfifowr <= rxdone and ((not rxstoperr) and (not rxparerr) and (not rxstop2err) and (not rxfifofull));
	process (sys_clk, crstn)begin
		if (crstn = '0') then
			R34(6 downto 1) <= (others => '0');
		elsif (sys_clk' event and sys_clk = '1') then
			if (rxfifofull = '1' and rxdone = '1') then
				R34(6) <= '1';
			elsif (RxOVC = '1') then
				R34(6) <= '0';
			end if;
			if (rxstoperr = '1' or rxstop2err = '1') then
				R34(4) <= '1';
			elsif (rxfifowr = '1') then
				R34(4) <= '0';
			end if;
			if (rxparerr = '1') then
				R34(3) <= '1';
			elsif (rxfifowr = '1') then
				R34(3) <= '0';
			end if;
		end if;
	end process;
	R34(0) <= rxbusy;

	rxfifowdat <= rxbyte;

	process (sys_clk, crstn)begin
		if (crstn = '0') then
			txdivcount <= 0;
		elsif (sys_clk' event and sys_clk = '1') then
			txsft <= '0';
			if (txrate(4) = '0' and sftm = '1') then
				if (txdivcount = 0) then
					txsft <= '1';
					if (txrate(3) = '0') then
						txdivcount <= 3;
					else
						txdivcount <= 7;
					end if;
				else
					txdivcount <= txdivcount - 1;
					if (txrate(3) = '0') then
						if (txdivcount > 3) then
							txdivcount <= 3;
						end if;
					else
						if (txdivcount > 7) then
							txdivcount <= 7;
						end if;
					end if;
				end if;
			elsif (txrate(4) = '1' and sftf = '1') then
				if (txdivcount = 0) then
					txsft <= '1';
					case txrate(3 downto 0) is
						when x"8" =>
							txdivcount <= 15;
						when x"9" =>
							txdivcount <= 31;
						when x"a" =>
							txdivcount <= 63;
						when x"b" =>
							txdivcount <= 127;
						when x"c" =>
							txdivcount <= 255;
						when x"d" =>
							txdivcount <= 511;
						when x"e" =>
							txdivcount <= 1023;
						when x"f" =>
							txdivcount <= 2047;
						when others =>
							txdivcount <= 7;
					end case;
				else
					txdivcount <= txdivcount - 1;
					case txrate(3 downto 0) is
						when x"8" =>
							if (txdivcount > 15) then
								txdivcount <= 15;
							end if;
						when x"9" =>
							if (txdivcount > 31) then
								txdivcount <= 31;
							end if;
						when x"a" =>
							if (txdivcount > 63) then
								txdivcount <= 63;
							end if;
						when x"b" =>
							if (txdivcount > 127) then
								txdivcount <= 127;
							end if;
						when x"c" =>
							if (txdivcount > 255) then
								txdivcount <= 255;
							end if;
						when x"d" =>
							if (txdivcount > 511) then
								txdivcount <= 511;
							end if;
						when x"e" =>
							if (txdivcount > 1023) then
								txdivcount <= 1023;
							end if;
						when x"f" =>
						when others =>
							if (txdivcount > 7) then
								txdivcount <= 7;
							end if;
					end case;
				end if;
			end if;
		end if;
	end process;

	process (sys_clk, crstn)
		variable vlen : integer range 1 to 13;
		variable par : std_logic;
		variable par4 : std_logic_vector(3 downto 0);
	begin
		if (crstn = '0') then
			txwr <= '0';
			txdata <= (others => '0');
			txfiford <= '0';
			txframelen <= 1;
		elsif (sys_clk' event and sys_clk = '1') then
			txwr <= '0';
			txfiford <= '0';
			if (txemp = '1' and txfifoemp = '0') then
				txwr <= '1';
				txfiford <= '1';
				if (TxCL = '0') then
					txdata(7 downto 0) <= txfifordat;
					vlen := 8;
				else
					txdata(6 downto 0) <= txfifordat(6 downto 0);
					vlen := 7;
				end if;
				if (TxPE = '1') then
					if (TxPL = '0') then
						par := TxEO;
						for i in 0 to 7 loop
							if (TxCL = '0' or i < 7) then
								par := par xor txfifordat(i);
							end if;
						end loop;
						txdata(vlen) <= par;
						vlen := vlen + 1;
					else
						par4 := (others => TxEO);
						if (TxCL = '0') then
							par4 := par4 xor txfifordat(3 downto 0) xor txfifordat(7 downto 4);
						else
							par4 := par4 xor txfifordat(3 downto 0) xor ('0' & txfifordat(6 downto 4));
						end if;
						txdata(vlen + 3 downto vlen) <= par4;
						vlen := vlen + 4;
					end if;
				end if;
				if (TxSL = '1') then
					txdata(vlen) <= not TxST;
					vlen := vlen + 1;
				end if;
				txframelen <= vlen;
			end if;
		end if;
	end process;

	txunit : txframe generic map(
		13, 3) port map(
		SD => TxD,
		DRCNT => txbusy,
		SUSPEND => suspend,

		SFT => txsft,
		WIDTH => "100",
		LEN => txframelen,
		STPLEN => 2,

		DATA => txdata,
		WRITE => txwr,
		BUFEMP => txemp,

		clk => sys_clk,
		rstn => crstn
	);
end rtl;