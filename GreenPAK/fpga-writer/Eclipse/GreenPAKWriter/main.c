/*
 * main.c
 *
 *  Created on: 2023/05/01
 *      Author: ohnaka
 */
#include "sys/alt_stdio.h"
#include "system.h"

#include <string.h>
#include <unistd.h>
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
#define	TRUE				-1
#define	FALSE				0
#define I2C_SLAVE_MEM		(SLAVE_MEM_BASE)			// I2C Slaveのメモリアドレス
#define I2C_SLAVE_SIZE		(SLAVE_MEM_SIZE_VALUE)		// I2C Slaveのメモリサイズ
#define I2C_MASTER_NAME		(I2C_0_NAME)				// I2C Masterのデバイス名
#define FIFO_CSR			(FIFO_RX_IN_CSR_BASE)		// On-Chip FIFOのレジスタアドレス
#define FIFO_DATA			(FIFO_RX_OUT_BASE)			// On-Chip FIFOのメモリアドレス
#define FIFO_IRQ_CTRL_ID	(FIFO_RX_IN_CSR_IRQ_INTERRUPT_CONTROLLER_ID)	// On-Chip FIFOのIRQコントローラID
#define FIFO_IRQ			(FIFO_RX_IN_CSR_IRQ)		// On-Chip FIFOのIRQ番号
#define MSGDMA_CSR			(MSGDMA_TX_CSR_NAME)		// mSGDMAのレジスタアドレス

/***********************************************************************************
 *  variables
 ***********************************************************************************/
volatile int stop = FALSE;	// I2C 通信停止フラグ

/***********************************************************************************
 *  proto types
 ***********************************************************************************/
void dump(unsigned char *adr, int size);	// メモリダンプ

/***********************************************************************************
 *  interrupt handler
 ***********************************************************************************/
// On-Chip FIFO 割り込みハンドラ
static void fifo_callback(void * context)
{
	int status;
	alt_u32 csr = (alt_u32)context;
	alt_irq_context cpu_sr;

    // 全割り込みをディセーブル
	cpu_sr = alt_irq_disable_all();

	// FIFO のステータスを読み出す
	status = altera_avalon_fifo_read_status(csr, ALTERA_AVALON_FIFO_IENABLE_ALL);

	// FULL か ALMOSTFULL なら I2C 通信停止フラグを立てる
	if(status & (ALTERA_AVALON_FIFO_STATUS_AF_MSK | ALTERA_AVALON_FIFO_STATUS_F_MSK))
	{
		stop = TRUE;
	}
	// イベントのクリア
	altera_avalon_fifo_clear_event(csr, (alt_u32)status);
    // 全割り込みをイネーブル
	alt_irq_enable_all(cpu_sr);
}

// I2C Master 割り込みハンドラ
static void i2c_callback(void * context)
{
    ALT_AVALON_I2C_DEV_t *i2c_dev = (ALT_AVALON_I2C_DEV_t *) context;
    alt_u32 status;
    alt_irq_context cpu_sr;

    // 全割り込みをディセーブル
	cpu_sr = alt_irq_disable_all();

	// I2C Masterのステータスを読み出す
    alt_avalon_i2c_int_status_get(i2c_dev, &status);

    // ステータスを出力(テスト用)
    printf("I2C Master Error Interrupt:%X\n", (int)status);

    // I2C 割り込みをディセーブル
    alt_avalon_i2c_int_disable(i2c_dev,ALT_AVALON_I2C_ISR_ALLINTS_MSK);

    // I2C 割り込みをクリア
    alt_avalon_i2c_int_clear(i2c_dev,ALT_AVALON_I2C_ISR_ALL_CLEARABLE_INTS_MSK);

    // I2C 割り込みをイネーブル
    alt_avalon_i2c_enable(i2c_dev);

    // 全割り込みをイネーブル
	alt_irq_enable_all(cpu_sr);
}

/***********************************************************************************
 *  main function
 ***********************************************************************************/
int main()
{
	int i;

    alt_printf("Hello from Nios II !!\n");

	// mSGDMA
	alt_msgdma_dev *tx_dma;
	alt_msgdma_standard_descriptor wr_desc, rd_desc;
	int dma_status;

	// I2C Master
	ALT_AVALON_I2C_DEV_t *i2c_dev;
	ALT_AVALON_I2C_STATUS_CODE i2c_status;

	// FIFO
	int fifo_status;

	// I2C Slave memory(非キャッシュ領域でポインタ生成)
	unsigned char *slv_buff = (unsigned char*)(I2C_SLAVE_MEM | 0x80000000);

	// I2C Command
	// アドレス 0x00 に 4-byte を書き込む
	unsigned char wr_cmd[][2] = {{0x02, 0xAA},	// Start , Device Address, W/R=0
								 {0x00, 0x00},	// Write address
								 {0x00, 0xAB},	// Write Data[0]
								 {0x00, 0xBC},	// Write Data[1]
								 {0x00, 0xCD},	// Write Data[2]
								 {0x01, 0xDE}};	// Write Data[3], Stop
	// アドレス 0x00 から 4-byte を読み出す
	unsigned char rd_cmd[][2] = {{0x02, 0xAA},	// Start , Device Address, W/R=0
								 {0x01, 0x00},	// Read Address, Stop
								 {0x02, 0xAB},	// Start, Device Address, W/R=1
								 {0x00, 0x00},	// Read Data[0]
								 {0x00, 0x00},	// Read Data[1]
								 {0x00, 0x00},	// Read Data[2]
								 {0x01, 0x00}};	// Read Data[3], Stop

	// I2C Slave メモリを 0xFF でクリア(書込みの状態を分かりやすくするため 0xFF で Fill)
	memset(slv_buff, 0xFF, I2C_SLAVE_SIZE);

	// === I2C Master 関連の初期化 ===
	// I2C Master をオープン
	i2c_dev = alt_avalon_i2c_open(I2C_MASTER_NAME);
	if (NULL == i2c_dev)
	{
		printf("Error:I2C Mater Open Fail\n");
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
		printf("Error:I2C Mater Enable Fail\n");
    	return FALSE;
    }

	// === On-Chip FIFO 関連の初期化 ===
	// On-Chip FIFO の初期化(10-word 蓄積されたら  ALMOSTFULL 割り込み発生）
	fifo_status = altera_avalon_fifo_init(FIFO_CSR, (ALTERA_AVALON_FIFO_IENABLE_AF_MSK | ALTERA_AVALON_FIFO_IENABLE_F_MSK), 1, 10);
	if(ALTERA_AVALON_FIFO_OK != fifo_status)
	{
		printf("Error:FIFO init Fail[%d]\n", fifo_status);
		return FALSE;
	}
	// On-Chip FIFO 割り込みハンドラを登録
	alt_ic_isr_register(FIFO_IRQ_CTRL_ID, FIFO_IRQ, fifo_callback, (void*)FIFO_CSR, 0x0);

	// === mSGDMA 関連の初期化 ===
	// mSGDMA をオープン
	tx_dma = alt_msgdma_open(MSGDMA_CSR);
	if(NULL == tx_dma)
	{
		printf("Error:TX mSGDMA Open Fail\n");
		return FALSE;
	}

	for(i = 1;;i ++)
	{
		// キャッシュフラッシュ
		alt_dcache_flush_all();

		// I2C Write用ディスクリプタの登録
		dma_status = alt_msgdma_construct_standard_mm_to_st_descriptor(tx_dma, &wr_desc, (alt_u32*)wr_cmd, sizeof(wr_cmd),
																	   ALTERA_MSGDMA_DESCRIPTOR_CONTROL_TRANSFER_COMPLETE_IRQ_MASK);
		if(0 != dma_status)
		{
			printf("Error:DMA descriptor Fail[%d]\n", dma_status);
			return FALSE;
		}
		// I2C Master による Write コマンドの DMA 起動
		dma_status = alt_msgdma_standard_descriptor_sync_transfer(tx_dma, &wr_desc);
		if(0 != dma_status)
		{
			printf("Error:DMA async trans Fail[%d]\n", dma_status);
			return FALSE;
		}

		// I2C Read用ディスクリプタの登録
		dma_status = alt_msgdma_construct_standard_mm_to_st_descriptor(tx_dma, &rd_desc, (alt_u32*)rd_cmd, sizeof(rd_cmd),
																	   ALTERA_MSGDMA_DESCRIPTOR_CONTROL_TRANSFER_COMPLETE_IRQ_MASK);
		if(0 != dma_status)
		{
			printf("Error:DMA descriptor Fail[%d]\n", dma_status);
			return FALSE;
		}
		// I2C Master による Read コマンドの DMA 起動
		dma_status = alt_msgdma_standard_descriptor_sync_transfer(tx_dma, &rd_desc);
		if(0 != dma_status)
		{
			printf("Error:DMA async trans Fail[%d]\n", dma_status);
			return FALSE;
		}

		// 書込みアドレスと値を変更
		wr_cmd[1][1] = i * 0x10;	// 書込みアドレス = i * 0x10
		wr_cmd[2][1] = i + 1;		// 書込みデータ[0] = i + 1
		wr_cmd[3][1] = i + 2;		// 書込みデータ[0] = i + 2
		wr_cmd[4][1] = i + 3;		// 書込みデータ[0] = i + 3
		wr_cmd[5][1] = i + 4;		// 書込みデータ[0] = i + 4

		// 読出しアドレスを変更
		rd_cmd[1][1] = i * 0x10;	// 読出しアドレス = i * 0x10

		// On-Chip FIFO の割り込みで FULL か ALMOSTFULL(10) なら終了
		if(stop == TRUE)
		{
			break;
		}
	}

	// On-Chip FIFO のレベルを取得
	int lev = altera_avalon_fifo_read_level(FIFO_CSR);
	printf("\nRead Count:%d\n", lev);

	printf("Read Data:");
	// On-Chip FIFO からデータを読み出してコンソール出力
	for(i = 0;i < lev;i ++)
	{
		int data;
		altera_avalon_read_fifo(FIFO_DATA, FIFO_CSR, &data);
		printf("%08X,", data);
	}

	printf("\n\n=== I2C Slave Dump ===");
	// I2C Slave メモリのダンプ
	dump(slv_buff, I2C_SLAVE_SIZE);


    while(1) {
      int reg;
      reg = *(volatile unsigned char *) PIO_DIPSW_BASE;
      *(volatile unsigned char *) PIO_LED_BASE = reg;
    }

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

	printf("\n0000: ");
	for(i = 0;i < size;i ++)
	{
		ucData = adr[i];
		if((i % 16 == 15) && (i < size - 1))
		{
			printf("%02X \n%04X: ", ucData, i + 1);
		}else
		{
			printf("%02X ", ucData);
		}
	}
	printf("\n");
}


