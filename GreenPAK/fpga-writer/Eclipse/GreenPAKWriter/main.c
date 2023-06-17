/*
 * main.c
 *
 *  Created on: 2023/05/01
 *      Author: kunichiko
 */
#include "sys/alt_stdio.h"
#include "system.h"

#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include <sys/alt_alarm.h>
#include <sys/alt_irq.h>
#include <sys/alt_cache.h>
#include <altera_avalon_i2c.h>
#include <altera_avalon_fifo.h>
#include <altera_avalon_fifo_util.h>
#include <altera_msgdma_descriptor_regs.h>
#include <altera_msgdma_csr_regs.h>
#include <altera_msgdma.h>

/***********************************************************************************
 *  definitions (define, enum, typedef, etc..)
 ***********************************************************************************/
#define TRUE -1
#define FALSE 0
#define I2C_SLAVE_MEM (SLAVE_MEM_BASE)								  // I2C Slaveのメモリアドレス
#define I2C_SLAVE_SIZE (SLAVE_MEM_SIZE_VALUE)						  // I2C Slaveのメモリサイズ
#define I2C_MASTER_NAME (I2C_0_NAME)								  // I2C Masterのデバイス名
#define FIFO_CSR (FIFO_RX_IN_CSR_BASE)								  // On-Chip FIFOのレジスタアドレス
#define FIFO_DATA (FIFO_RX_OUT_BASE)								  // On-Chip FIFOのメモリアドレス
#define FIFO_IRQ_CTRL_ID (FIFO_RX_IN_CSR_IRQ_INTERRUPT_CONTROLLER_ID) // On-Chip FIFOのIRQコントローラID
#define FIFO_IRQ (FIFO_RX_IN_CSR_IRQ)								  // On-Chip FIFOのIRQ番号
#define MSGDMA_CSR (MSGDMA_TX_CSR_NAME)								  // mSGDMAのレジスタアドレス

// VGA-textテスト
unsigned char (*textram)[128] = (unsigned char (*)[128])TEXTRAM_BASE;

// GreenPAK書き込み用ROMイメージのアドレス
unsigned char *nvm_rom = (unsigned char *)ONCHIP_NVM_ROM_BASE;

/*
 GreenPAKのI2Cアドレス:
 0x08 : レジスタ
 0x09 : レジスタ
 0x0A : NVM
 0x0B : EEPROM
*/
#define GP_I2C_ADDR_REG0 0x08
#define GP_I2C_ADDR_REG1 0x09
#define GP_I2C_ADDR_NVM 0x0A
#define GP_I2C_ADDR_EEPROM 0x0B

/***********************************************************************************
 *  variables
 ***********************************************************************************/
volatile int stop = FALSE; // I2C 通信停止フラグ

/***********************************************************************************
 *  proto types
 ***********************************************************************************/
void dump(unsigned char *adr, int size); // メモリダンプ

/***********************************************************************************
 *  wait
 ***********************************************************************************/
void wait_msec(uint32_t msec)
{
	uint32_t wait = msec * 1000; // 実測で１ループ１マイクロ秒くらい
	for (uint32_t i = 0; i < wait; i++)
	{
		// NOP命令を実行することで、1クロックサイクルのウエイトを作る
		asm("nop");
	}
}

/***********************************************************************************
 *  log
 ***********************************************************************************/
unsigned int vgatext_cur_x = 0;
unsigned int vgatext_cur_y = 0;

#define KXLOG_BUFSIZE 128
char kxlog_buffer[KXLOG_BUFSIZE];

void kxlog(const char *format, ...)
{
	va_list args;
	va_start(args, format);
	int n = vsnprintf(kxlog_buffer, KXLOG_BUFSIZE, format, args);
	va_end(args);

	if (n < 0 || n > KXLOG_BUFSIZE)
	{
		return;
	}
	kxlog_buffer[n] = 0x00;

	// JTAG UARTに出力
	// alt_printf(kxlog_buffer);

	// VGA-Textに出力
	for (int i = 0; i < n; i++)
	{
		if (kxlog_buffer[i] == 0x0a || kxlog_buffer[i] == 0x0d)
		{
			vgatext_cur_x = 0;
			vgatext_cur_y++;
		}
		else
		{
			textram[vgatext_cur_y % 64][vgatext_cur_x++] = kxlog_buffer[i];
		}
		if (vgatext_cur_x >= 96)
		{
			vgatext_cur_x = 0;
			vgatext_cur_y++;
		}
		if (vgatext_cur_y >= 36)
		{
			*(volatile unsigned char *)PIO_SCROLL_Y_BASE = (vgatext_cur_y - 35) % 64;
		}
		else
		{
			*(volatile unsigned char *)PIO_SCROLL_Y_BASE = 0;
		}
		if (vgatext_cur_x == 0)
		{
			for (int x = 0; x < 128; x++)
			{
				textram[vgatext_cur_y % 64][x] = 0x20;
			}
		}
	}
}

/***********************************************************************************
 *  interrupt handler
 ***********************************************************************************/
// On-Chip FIFO 割り込みハンドラ
static void fifo_callback(void *context)
{
	int status;
	alt_u32 csr = (alt_u32)context;
	alt_irq_context cpu_sr;

	// 全割り込みをディセーブル
	cpu_sr = alt_irq_disable_all();

	// FIFO のステータスを読み出す
	status = altera_avalon_fifo_read_status(csr, ALTERA_AVALON_FIFO_IENABLE_ALL);

	// FULL か ALMOSTFULL なら I2C 通信停止フラグを立てる
	if (status & (ALTERA_AVALON_FIFO_STATUS_AF_MSK | ALTERA_AVALON_FIFO_STATUS_F_MSK))
	{
		stop = TRUE;
	}
	// イベントのクリア
	altera_avalon_fifo_clear_event(csr, (alt_u32)status);
	// 全割り込みをイネーブル
	alt_irq_enable_all(cpu_sr);
}

// I2C Master 割り込みハンドラ
static void i2c_callback(void *context)
{
	ALT_AVALON_I2C_DEV_t *i2c_dev = (ALT_AVALON_I2C_DEV_t *)context;
	alt_u32 status;
	alt_irq_context cpu_sr;

	// 全割り込みをディセーブル
	cpu_sr = alt_irq_disable_all();

	// I2C Masterのステータスを読み出す
	alt_avalon_i2c_int_status_get(i2c_dev, &status);

	// ステータスを出力(テスト用)
	kxlog("I2C Master Error Interrupt:%X\n", (int)status);

	// I2C 割り込みをディセーブル
	alt_avalon_i2c_int_disable(i2c_dev, ALT_AVALON_I2C_ISR_ALLINTS_MSK);

	// I2C 割り込みをクリア
	alt_avalon_i2c_int_clear(i2c_dev, ALT_AVALON_I2C_ISR_ALL_CLEARABLE_INTS_MSK);

	// I2C 割り込みをイネーブル
	alt_avalon_i2c_enable(i2c_dev);

	// 全割り込みをイネーブル
	alt_irq_enable_all(cpu_sr);
}

// mSGDMA
alt_msgdma_dev *tx_dma;
alt_msgdma_standard_descriptor wr_desc, rd_desc, er_desc;
int dma_status;

// I2C Master
ALT_AVALON_I2C_DEV_t *i2c_dev;
ALT_AVALON_I2C_STATUS_CODE i2c_status;

// FIFO
int fifo_status;

int init()
{
	// VGA-Textの初期化
	for (int y = 0; y < 64; y++)
	{
		for (int x = 0; x < 128; x++)
		{
			textram[y][x] = 0x20;
		}
	}

	// === I2C Master 関連の初期化 ===
	// I2C Master をオープン
	i2c_dev = alt_avalon_i2c_open(I2C_MASTER_NAME);
	if (NULL == i2c_dev)
	{
		kxlog("Error:I2C Mater Open Fail\n");
		return FALSE;
	}

	// I2C Master 初期化
	alt_avalon_i2c_init(i2c_dev);
	// I2C Master 割り込みハンドラの登録と割り込み有効
	alt_ic_isr_register(i2c_dev->irq_controller_ID, i2c_dev->irq_ID, i2c_callback, i2c_dev, 0x0);
	alt_avalon_i2c_int_enable(i2c_dev, ALT_AVALON_I2C_ISR_ALL_CLEARABLE_INTS_MSK);
	// I2C Master 起動
	i2c_status = alt_avalon_i2c_enable(i2c_dev);
	if (ALT_AVALON_I2C_SUCCESS != i2c_status)
	{
		kxlog("Error:I2C Mater Enable Fail\n");
		return FALSE;
	}

	// === On-Chip FIFO 関連の初期化 ===
	// On-Chip FIFO の初期化(10-word 蓄積されたら  ALMOSTFULL 割り込み発生）
	fifo_status = altera_avalon_fifo_init(FIFO_CSR, (ALTERA_AVALON_FIFO_IENABLE_AF_MSK | ALTERA_AVALON_FIFO_IENABLE_F_MSK), 1, 10);
	if (ALTERA_AVALON_FIFO_OK != fifo_status)
	{
		kxlog("Error:FIFO init Fail[%d]\n", fifo_status);
		return FALSE;
	}
	// On-Chip FIFO 割り込みハンドラを登録
	alt_ic_isr_register(FIFO_IRQ_CTRL_ID, FIFO_IRQ, fifo_callback, (void *)FIFO_CSR, 0x0);

	// === mSGDMA 関連の初期化 ===
	// mSGDMA をオープン
	tx_dma = alt_msgdma_open(MSGDMA_CSR);
	if (NULL == tx_dma)
	{
		kxlog("Error:TX mSGDMA Open Fail\n");
		return FALSE;
	}
	return TRUE;
}

// I2C Command
// アドレス 0x00 から 16-byte を読み出す
unsigned char rd_cmd[][2] = {{0x02, 0x00},	// Start , Device Address, W/R=0
							 {0x01, 0x00},	// Read Address, Stop
							 {0x02, 0x00},	// Start, Device Address, W/R=1
							 {0x00, 0x00},	// Read Data[0]
							 {0x00, 0x00},	// Read Data[1]
							 {0x00, 0x00},	// Read Data[2]
							 {0x00, 0x00},	// Read Data[3]
							 {0x00, 0x00},	// Read Data[4]
							 {0x00, 0x00},	// Read Data[5]
							 {0x00, 0x00},	// Read Data[6]
							 {0x00, 0x00},	// Read Data[7]
							 {0x00, 0x00},	// Read Data[8]
							 {0x00, 0x00},	// Read Data[9]
							 {0x00, 0x00},	// Read Data[A]
							 {0x00, 0x00},	// Read Data[B]
							 {0x00, 0x00},	// Read Data[C]
							 {0x00, 0x00},	// Read Data[D]
							 {0x00, 0x00},	// Read Data[E]
							 {0x01, 0x00}}; // Read Data[F], Stop

unsigned char er_cmd[][2] = {{0x02, (GP_I2C_ADDR_REG0 << 1) + 0}, // Start , Device Address, W/R=0
							 {0x00, 0xE3},						  // Erase
							 {0x01, 0x00}};						  // Block Number, Stop

unsigned char wr_cmd[][2] = {{0x02, 0x00},	// Start, Device Address, W/R=0
							 {0x00, 0x00},	// Write block number
							 {0x00, 0x00},	// Write Data[0]
							 {0x00, 0x00},	// Write Data[1]
							 {0x00, 0x00},	// Write Data[2]
							 {0x00, 0x00},	// Write Data[3]
							 {0x00, 0x00},	// Write Data[4]
							 {0x00, 0x00},	// Write Data[5]
							 {0x00, 0x00},	// Write Data[6]
							 {0x00, 0x00},	// Write Data[7]
							 {0x00, 0x00},	// Write Data[8]
							 {0x00, 0x00},	// Write Data[9]
							 {0x00, 0x00},	// Write Data[A]
							 {0x00, 0x00},	// Write Data[B]
							 {0x00, 0x00},	// Write Data[C]
							 {0x00, 0x00},	// Write Data[D]
							 {0x00, 0x00},	// Write Data[E]
							 {0x01, 0x00}}; // Write Data[F], Stop

/*
 GreenPAK の NVM(回路のコンフィグ情報)やEEPROMの情報を読み出します。
 i2c_addr : GP_I2C_ADDR_NVM or GP_I2C_ADDR_EEPROM
 buf : 読み出し用のバッファ(256バイト)
*/
int read_gp_rom(unsigned char i2c_addr, unsigned char *buf)
{
	int i, j;

	for (i = 0; i < 16; i++)
	{
		rd_cmd[0][1] = (i2c_addr << 1) + 0;
		rd_cmd[2][1] = (i2c_addr << 1) + 1;
		// 読出しアドレスを変更
		rd_cmd[1][1] = i * 0x10; // 読出しアドレス = i * 0x10

		// キャッシュフラッシュ
		alt_dcache_flush_all();

		// I2C Read用ディスクリプタの登録
		dma_status = alt_msgdma_construct_standard_mm_to_st_descriptor(tx_dma, &rd_desc, (alt_u32 *)rd_cmd, sizeof(rd_cmd),
																	   ALTERA_MSGDMA_DESCRIPTOR_CONTROL_TRANSFER_COMPLETE_IRQ_MASK);
		if (-EINVAL == dma_status)
		{
			kxlog("error\n");
		}
		if (0 != dma_status)
		{
			kxlog("Error:DMA descriptor Fail[%d] @%d\n", dma_status, i);
			return FALSE;
		}
		// I2C Master による Read コマンドの DMA 起動
		dma_status = alt_msgdma_standard_descriptor_sync_transfer(tx_dma, &rd_desc);
		if (0 != dma_status)
		{
			kxlog("Error:DMA async trans Fail[%d]\n", dma_status);
			return FALSE;
		}

		// On-Chip FIFO に4ワード(16バイト)貯まるのを待つ
		int count = 0;
		int lev;
		while ((lev = altera_avalon_fifo_read_level(FIFO_CSR)) < 4)
		{
			if (count++ >= 1000)
			{
				kxlog(".");
				count = 0;
			}
		}
		// kxlog("Read Data:");
		//  On-Chip FIFO からデータを読み出してバッファに書く
		for (j = 0; j < 4; j++)
		{
			int data;
			altera_avalon_read_fifo(FIFO_DATA, FIFO_CSR, &data);
			// kxlog("%08X,", data);
			*(buf++) = ((unsigned char *)(&data))[0];
			*(buf++) = ((unsigned char *)(&data))[1];
			*(buf++) = ((unsigned char *)(&data))[2];
			*(buf++) = ((unsigned char *)(&data))[3];
		}
		kxlog("*", i);
		wait_msec(10);
	}
	return TRUE;
}

/*
 GreenPAK の NVM(回路のコンフィグ情報)を削除します。
*/
int erase_gp_rom(int nvm_or_eeprom);
int erase_gp_rom_block(int nvm_or_eeprom, int block);

int erase_gp_nvm()
{
	return erase_gp_rom(0);
}

int erase_gp_eeprom()
{
	return erase_gp_rom(1);
}

int erase_gp_rom(int nvm_or_eeprom)
{
	for (int i = 0; i < 16; i++)
	{
		int ret = erase_gp_rom_block(nvm_or_eeprom, i);
		if (ret != TRUE)
		{
			return FALSE;
		}
	}
	return TRUE;
}

int erase_gp_rom_block(int nvm_or_eeprom, int block)
{
	// 削除対象ブロック番号
	er_cmd[2][1] = 0x80 + (0x10 * nvm_or_eeprom) + block;
	// キャッシュフラッシュ
	alt_dcache_flush_all();

	// I2C Erase用ディスクリプタの登録
	dma_status = alt_msgdma_construct_standard_mm_to_st_descriptor(tx_dma, &er_desc, (alt_u32 *)er_cmd, sizeof(er_cmd),
																   ALTERA_MSGDMA_DESCRIPTOR_CONTROL_TRANSFER_COMPLETE_IRQ_MASK);
	if (-EINVAL == dma_status)
	{
		kxlog("error\n");
	}
	if (0 != dma_status)
	{
		kxlog("Error:DMA descriptor Fail[%d] @%d\n", dma_status, block);
		return FALSE;
	}
	// I2C Master による Erase コマンドの DMA 起動
	dma_status = alt_msgdma_standard_descriptor_sync_transfer(tx_dma, &er_desc);
	if (0 != dma_status)
	{
		kxlog("Error:DMA async trans Fail[%d]\n", dma_status);
		return FALSE;
	}
	kxlog("*");
	wait_msec(100);
	return TRUE;
}

/*
 GreenPAK の NVM(回路のコンフィグ情報)やEEPROMの情報を書き換えます。
 NVMを書き換える際は、事前に消去しておく必要があります。
 i2c_addr : GP_I2C_ADDR_NVM or GP_I2C_ADDR_EEPROM
 num_blocks : 書き換えるブロック数(0-16)
 buf : 書き込むデータ(num_blocks * 16バイト)
*/
int write_gp_rom(unsigned char i2c_addr, int num_blocks, unsigned char *buf)
{
	if (num_blocks > 16)
	{
		return FALSE;
	}
	wait_msec(1000);
	for (int block = 0; block < num_blocks; block++)
	{
		kxlog("[%d", block);
		wait_msec(100);
		int nvm_or_eeprom = i2c_addr == GP_I2C_ADDR_NVM ? 0 : 1;
		erase_gp_rom_block(nvm_or_eeprom, block);
		wait_msec(100);

		kxlog("E");
		wait_msec(100);

		// アドレスセット
		wr_cmd[0][1] = (i2c_addr << 1) + 0;
		// 書き込み対象のブロックを変更
		wr_cmd[1][1] = block * 16;
		// 書き込むデータをセット
		for (int j = 0; j < 16; j++)
		{
			wr_cmd[2 + j][1] = buf[block * 16 + j];
		}

		// キャッシュフラッシュ
		alt_dcache_flush_all();

		// I2C Write用ディスクリプタの登録
		dma_status = alt_msgdma_construct_standard_mm_to_st_descriptor(tx_dma, &wr_desc, (alt_u32 *)wr_cmd, sizeof(wr_cmd),
																	   ALTERA_MSGDMA_DESCRIPTOR_CONTROL_TRANSFER_COMPLETE_IRQ_MASK);
		if (0 != dma_status)
		{
			// dma_status が -22 (-EINVAL:パラメーターエラー) になる場合は、
			// スタックオーバーフローなどでメモリ破壊が起こっている可能性を考慮する
			kxlog("Error:DMA descriptor Fail[%d] @%d\n", dma_status, block);
			return FALSE;
		}
		// I2C Master による Write コマンドの DMA 起動
		dma_status = alt_msgdma_standard_descriptor_sync_transfer(tx_dma, &wr_desc);
		if (0 != dma_status)
		{
			kxlog("Error:DMA async trans Fail[%d]\n", dma_status);
			return FALSE;
		}
		wait_msec(100);
		kxlog("]");
	}
	kxlog("\n");
	return TRUE;
}

/***********************************************************************************
 *  sub function
 ***********************************************************************************/
void dump(unsigned char *adr, int size)
{
	int i;
	unsigned char ucData;

	// キャッシュフラッシュ
	alt_dcache_flush_all();

	kxlog("0000: ");
	for (i = 0; i < size; i++)
	{
		ucData = adr[i];
		if ((i % 16 == 15) && (i < size - 1))
		{
			kxlog("%02X \n%04X: ", ucData, i + 1);
		}
		else
		{
			kxlog("%02X ", ucData);
		}
	}
	kxlog("\n");
}

unsigned char rom_buffer[256];

/*
serial_number : 0-65535
*/
int eeprom_write(int board_version, int board_version_minor, int serial_number)
{
	int ret;
	// EEPROM 書き換え
	kxlog("Writing EEPROM\n");
	for (int i = 0; i < 256; i++)
	{
		rom_buffer[i] = 0;
	}
	rom_buffer[0x09] = 0x07; // all peripheral enabled
	rom_buffer[0x0d] = 0x0c; // Mercury PCM Volume
	rom_buffer[0x13] = 0x05; // MIDI routing
	rom_buffer[0x6e] = 0x00; // 書き込み回数(U)
	rom_buffer[0x6f] = 0x00; // 書き込み回数(L)
	// CRC領域
	// CRCは以下のサイトで計算可能。もしくはKeplerXで書き込んでみる。
	// https://crccalc.com/
	rom_buffer[0x70] = 0xc3; // CRC for 0x00-0x0f
	rom_buffer[0x71] = 0xb6; // https://crccalc.com/?crc=000000000000000000070000000c0000&method=CRC-16/ARC&datatype=hex&outtype=0
	rom_buffer[0x72] = 0x05; // CRC f0r 0x10-0x1f
	rom_buffer[0x73] = 0x0c; // https://crccalc.com/?crc=00000005000000000000000000000000&method=CRC-16/ARC&datatype=hex&outtype=0
	rom_buffer[0x7e] = 0x68; // CRC f0r 0x70-0x7d
	rom_buffer[0x7f] = 0x47; // https://crccalc.com/?crc=c3b6050c00000000000000000000&method=CRC-16/ARC&datatype=hex&outtype=0

    // 定数領域
	rom_buffer[0xf0] = 'K'; // 0x4b
	rom_buffer[0xf1] = 'X'; // 0x58
	rom_buffer[0xf2] = (board_version << 4) | ((serial_number >> 8) & 0x0f);
	rom_buffer[0xf3] = serial_number & 0xff;
	rom_buffer[0xf4] = board_version;
	rom_buffer[0xf5] = board_version_minor;
	ret = write_gp_rom(GP_I2C_ADDR_EEPROM, 16, (unsigned char *)&rom_buffer);
	if (ret == FALSE)
	{
		return FALSE;
	}

	wait_msec(1000);

	// EEPROM読み出し
	kxlog("EEPROM\n");
	ret = read_gp_rom(GP_I2C_ADDR_EEPROM, (unsigned char *)&rom_buffer);
	if (ret == FALSE)
	{
		return FALSE;
	}
	// ダンプ
	kxlog("\n");
	dump((unsigned char *)&rom_buffer, 256);
	kxlog("\n");
	wait_msec(1000);
	return TRUE;
}

int nvm_write()
{
	int ret;
	// NVM 書き換え
	kxlog("Writing NVM\n");
	ret = write_gp_rom(GP_I2C_ADDR_NVM, 16, nvm_rom);
	if (ret == FALSE)
	{
		return FALSE;
	}

	wait_msec(1000);

	// NVM読み出し
	kxlog("NVM\n");
	ret = read_gp_rom(GP_I2C_ADDR_NVM, (unsigned char *)&rom_buffer);
	if (ret == FALSE)
	{
		return FALSE;
	}
	// ダンプ
	kxlog("\n");
	dump((unsigned char *)&rom_buffer, 256);
	kxlog("\n");
	wait_msec(1000);
	return TRUE;
}

/***********************************************************************************
 *  main function
 ***********************************************************************************/

int main()
{

	wait_msec(1000 * 8);

	int ret;

	// 初期化
	ret = init();
	if (ret == FALSE)
	{
		return FALSE;
	}

	kxlog("[Kepler-X GreenPAK Writer]\n");

	for (int i = 3; i > 0; i--)
	{
		kxlog("count: %d\n", i);
		wait_msec(1000);
	}

	kxlog("[Current contents]\n");

	// NVM読み出し
	kxlog("NVM\n");
	ret = read_gp_rom(GP_I2C_ADDR_NVM, (unsigned char *)&rom_buffer);
	if (ret == FALSE)
	{
		return FALSE;
	}
	// ダンプ
	kxlog("\n");
	dump((unsigned char *)&rom_buffer, 256);
	kxlog("\n");
	wait_msec(1000);

	// EEPROM読み出し
	kxlog("EEPROM\n");
	ret = read_gp_rom(GP_I2C_ADDR_EEPROM, (unsigned char *)&rom_buffer);
	if (ret == FALSE)
	{
		return FALSE;
	}
	// ダンプ
	kxlog("\n");
	dump((unsigned char *)&rom_buffer, 256);
	kxlog("\n");
	wait_msec(1000);

	if (TRUE)
	{
		kxlog("[Write contents]\n");

		nvm_write();

		// シリアル番号の振り方
		// 0-999     : 開発用
		// 1000-9999 : 頒布用
		// シリアル番号は、ボードメジャーバージョン(壱號機、弍號機など)の中でユニーク
		eeprom_write(
			1,	 // 弐號機
			0,	 // 2.0
			1000 // serial number
		);

		kxlog("[Write completed]\n");
	}
	// キー入力
	while (1)
	{
		int reg;
		reg = *(volatile unsigned char *)PIO_DIPSW_BASE;
		*(volatile unsigned char *)PIO_LED_BASE = reg;
	}

	return TRUE;
}
