`timescale 1 ns / 1 ns
//////////////////////////////////////////////////////////////////////////////////
// Company: Rehkopf
// Engineer: Rehkopf
// 
// Create Date:    01:13:46 05/09/2009 
// Design Name: 
// Module Name:    main 
// Project Name: 
// Target Devices: 
// Tool versions: 
// Description: Master Control FSM
//
// Dependencies: address
//
// Revision: 
// Revision 0.01 - File Created
// Additional Comments: 
//
//////////////////////////////////////////////////////////////////////////////////
module main(
  /* input clock */
  input CLKIN,

  /* SNES signals */
  input [23:0] SNES_ADDR_IN,
  input SNES_READ,
  input SNES_WRITE,
  input SNES_CS,
  inout [7:0] SNES_DATA,
  input SNES_CPU_CLK,
  input SNES_REFRESH,
  output SNES_IRQ,
  output SNES_DATABUS_OE,
  output SNES_DATABUS_DIR,
  input SNES_SYSCLK,

  input [7:0] SNES_PA,
  input SNES_PARD,
  input SNES_PAWR,
  
  /* SRAM signals */
  /* Bus 1: PSRAM, 128Mbit, 16bit, 70ns */
  inout [15:0] ROM_DATA,
  output [22:0] ROM_ADDR,
  output ROM_CE,
  output ROM_OE,
  output ROM_WE,
  output ROM_BHE,
  output ROM_BLE,

  /* Bus 2: SRAM, 4Mbit, 8bit, 45ns */
  inout [7:0] RAM_DATA,
  output [18:0] RAM_ADDR,
  output RAM_CE,
  output RAM_OE,
  output RAM_WE,

  /* MCU signals */
  input SPI_MOSI,
  inout SPI_MISO,
  input SPI_SS,
  inout SPI_SCK,
  input MCU_OVR,
  output MCU_RDY,
  
  output DAC_MCLK,
  output DAC_LRCK,
  output DAC_SDOUT,

  /* SD signals */
  input [3:0] SD_DAT,
  inout SD_CMD,
  inout SD_CLK,

  /* debug */
  output p113_out
);

wire CLK2;

reg [23:0] SNES_ADDR_r [2:0];
always @(posedge CLK2) begin
  SNES_ADDR_r[2] <= SNES_ADDR_r[1];
  SNES_ADDR_r[1] <= SNES_ADDR_r[0];
  SNES_ADDR_r[0] <= SNES_ADDR_IN;
end
wire [23:0] SNES_ADDR = SNES_ADDR_r[2] & SNES_ADDR_r[1];

wire dspx_dp_enable;

wire [7:0] spi_cmd_data;
wire [7:0] spi_param_data;
wire [7:0] spi_input_data;
wire [31:0] spi_byte_cnt;
wire [2:0] spi_bit_cnt;
wire [23:0] MCU_ADDR;
wire [2:0] MAPPER;
wire [23:0] SAVERAM_MASK;
wire [23:0] ROM_MASK;
wire [7:0] SD_DMA_SRAM_DATA;
wire [1:0] SD_DMA_TGT;
wire [10:0] SD_DMA_PARTIAL_START;
wire [10:0] SD_DMA_PARTIAL_END;

wire [10:0] dac_addr;
//wire [7:0] dac_volume;
wire [7:0] msu_volumerq_out;
wire [6:0] msu_status_out;
wire [31:0] msu_addressrq_out;
wire [15:0] msu_trackrq_out;
wire [13:0] msu_write_addr;
wire [13:0] msu_ptr_addr;
wire [7:0] MSU_SNES_DATA_IN;
wire [7:0] MSU_SNES_DATA_OUT;
wire [5:0] msu_status_reset_bits;
wire [5:0] msu_status_set_bits;

wire [14:0] bsx_regs;
wire [7:0] BSX_SNES_DATA_IN;
wire [7:0] BSX_SNES_DATA_OUT;
wire [7:0] bsx_regs_reset_bits;
wire [7:0] bsx_regs_set_bits;

wire [59:0] rtc_data;
wire [55:0] rtc_data_in;
wire [59:0] srtc_rtc_data_out;
wire [3:0] SRTC_SNES_DATA_IN;
wire [7:0] SRTC_SNES_DATA_OUT;

wire [7:0] DSPX_SNES_DATA_IN;
wire [7:0] DSPX_SNES_DATA_OUT;

wire [23:0] dspx_pgm_data;
wire [10:0] dspx_pgm_addr;
wire dspx_pgm_we;

wire [15:0] dspx_dat_data;
wire [10:0] dspx_dat_addr;
wire dspx_dat_we;

wire [7:0] featurebits;

wire [23:0] MAPPED_SNES_ADDR;
wire ROM_ADDR0;

wire [9:0] bs_page;
wire [8:0] bs_page_offset;
wire bs_page_enable;

sd_dma snes_sd_dma(
  .CLK(CLK2),
  .SD_DAT(SD_DAT),
  .SD_CLK(SD_CLK),
  .SD_DMA_EN(SD_DMA_EN),
  .SD_DMA_STATUS(SD_DMA_STATUS),
  .SD_DMA_SRAM_WE(SD_DMA_SRAM_WE),
  .SD_DMA_SRAM_DATA(SD_DMA_SRAM_DATA),
  .SD_DMA_NEXTADDR(SD_DMA_NEXTADDR),
  .SD_DMA_PARTIAL(SD_DMA_PARTIAL),
  .SD_DMA_PARTIAL_START(SD_DMA_PARTIAL_START),
  .SD_DMA_PARTIAL_END(SD_DMA_PARTIAL_END),
  .SD_DMA_START_MID_BLOCK(SD_DMA_START_MID_BLOCK),
  .SD_DMA_END_MID_BLOCK(SD_DMA_END_MID_BLOCK)
);

wire SD_DMA_TO_ROM = (SD_DMA_STATUS && (SD_DMA_TGT == 2'b00));

dac snes_dac(
  .clkin(CLK2),
  .sysclk(SNES_SYSCLK),
  .mclk(DAC_MCLK),
  .lrck(DAC_LRCK),
  .sdout(DAC_SDOUT),
  .we(SD_DMA_TGT==2'b01 ? SD_DMA_SRAM_WE : 1'b1),
  .pgm_address(dac_addr),
  .pgm_data(SD_DMA_SRAM_DATA),
  .DAC_STATUS(DAC_STATUS),
  .volume(msu_volumerq_out),
  .vol_latch(msu_volume_latch_out),
  .play(dac_play),
  .reset(dac_reset)
);

srtc snes_srtc (
  .clkin(CLK2),
  .addr_in(SNES_ADDR[0]),
  .data_in(SRTC_SNES_DATA_IN),
  .data_out(SRTC_SNES_DATA_OUT),
  .rtc_data_in(rtc_data),
  .reg_we(SNES_WRITE),
  .reg_oe(SNES_READ),
  .enable(srtc_enable),
  .rtc_data_out(srtc_rtc_data_out),
  .rtc_we(srtc_rtc_we),
  .reset(srtc_reset)
);

rtc snes_rtc (
  .clkin(CLKIN),
  .rtc_data(rtc_data),
  .rtc_data_in(rtc_data_in),
  .pgm_we(rtc_pgm_we),
  .rtc_data_in1(srtc_rtc_data_out),
  .we1(srtc_rtc_we)
);

msu snes_msu (
  .clkin(CLK2),
  .enable(msu_enable),
  .pgm_address(msu_write_addr),
  .pgm_data(SD_DMA_SRAM_DATA),
  .pgm_we(SD_DMA_TGT==2'b10 ? SD_DMA_SRAM_WE : 1'b1),
  .reg_addr(SNES_ADDR[2:0]),
  .reg_data_in(MSU_SNES_DATA_IN),
  .reg_data_out(MSU_SNES_DATA_OUT),
  .reg_oe(SNES_READ),
  .reg_we(SNES_WRITE),
  .status_out(msu_status_out),
  .volume_out(msu_volumerq_out),
  .volume_latch_out(msu_volume_latch_out),
  .addr_out(msu_addressrq_out),
  .track_out(msu_trackrq_out),
  .status_reset_bits(msu_status_reset_bits),
  .status_set_bits(msu_status_set_bits),
  .status_reset_we(msu_status_reset_we),
  .msu_address_ext(msu_ptr_addr),
  .msu_address_ext_write(msu_addr_reset)
);

bsx snes_bsx(
  .clkin(CLK2),
  .use_bsx(use_bsx),
  .pgm_we(bsx_regs_reset_we),
  .snes_addr(SNES_ADDR),
  .reg_data_in(BSX_SNES_DATA_IN),
  .reg_data_out(BSX_SNES_DATA_OUT),
  .reg_oe(SNES_READ),
  .reg_we(SNES_WRITE),
  .regs_out(bsx_regs),
  .reg_reset_bits(bsx_regs_reset_bits),
  .reg_set_bits(bsx_regs_set_bits),
  .data_ovr(bsx_data_ovr),
  .flash_writable(IS_FLASHWR),
  .rtc_data(rtc_data[59:0]),
  .bs_page_out(bs_page), // support only page 0000-03ff
  .bs_page_enable(bs_page_enable),
  .bs_page_offset(bs_page_offset)

);

spi snes_spi(
  .clk(CLK2),
  .MOSI(SPI_MOSI),
  .MISO(SPI_MISO),
  .SSEL(SPI_SS),
  .SCK(SPI_SCK),
  .cmd_ready(spi_cmd_ready),
  .param_ready(spi_param_ready),
  .cmd_data(spi_cmd_data),
  .param_data(spi_param_data),
  .endmessage(spi_endmessage),
  .startmessage(spi_startmessage),
  .input_data(spi_input_data),
  .byte_cnt(spi_byte_cnt),
  .bit_cnt(spi_bit_cnt)
);

upd77c25 snes_dspx (
  .DI(DSPX_SNES_DATA_IN),
  .DO(DSPX_SNES_DATA_OUT),
  .A0(DSPX_A0),
  .nCS(~dspx_enable),
  .nRD(SNES_READ),
  .nWR(SNES_WRITE),
  .RST(~dspx_reset),
  .CLK(CLK2),
  .PGM_WR(dspx_pgm_we),
  .PGM_DI(dspx_pgm_data),
  .PGM_WR_ADDR(dspx_pgm_addr),
  .DAT_WR(dspx_dat_we),
  .DAT_DI(dspx_dat_data),
  .DAT_WR_ADDR(dspx_dat_addr),
  .DP_nCS(~dspx_dp_enable),
  .DP_ADDR(SNES_ADDR[10:0])
);

reg [7:0] MCU_DINr;
wire [7:0] MCU_DOUT;

mcu_cmd snes_mcu_cmd(
  .clk(CLK2),
  .snes_sysclk(SNES_SYSCLK),
  .cmd_ready(spi_cmd_ready),
  .param_ready(spi_param_ready),
  .cmd_data(spi_cmd_data),
  .param_data(spi_param_data),
  .mcu_mapper(MAPPER),
  .mcu_write(MCU_WRITE),
  .mcu_data_in(MCU_DINr),
  .mcu_data_out(MCU_DOUT),
  .spi_byte_cnt(spi_byte_cnt),
  .spi_bit_cnt(spi_bit_cnt),
  .spi_data_out(spi_input_data),
  .addr_out(MCU_ADDR),
  .saveram_mask_out(SAVERAM_MASK),
  .rom_mask_out(ROM_MASK),
  .SD_DMA_EN(SD_DMA_EN),
  .SD_DMA_STATUS(SD_DMA_STATUS),
  .SD_DMA_NEXTADDR(SD_DMA_NEXTADDR),
  .SD_DMA_SRAM_DATA(SD_DMA_SRAM_DATA),
  .SD_DMA_SRAM_WE(SD_DMA_SRAM_WE),
  .SD_DMA_TGT(SD_DMA_TGT),
  .SD_DMA_PARTIAL(SD_DMA_PARTIAL),
  .SD_DMA_PARTIAL_START(SD_DMA_PARTIAL_START),
  .SD_DMA_PARTIAL_END(SD_DMA_PARTIAL_END),
  .SD_DMA_START_MID_BLOCK(SD_DMA_START_MID_BLOCK),
  .SD_DMA_END_MID_BLOCK(SD_DMA_END_MID_BLOCK),
  .dac_addr_out(dac_addr),
  .DAC_STATUS(DAC_STATUS),
//  .dac_volume_out(dac_volume),
//  .dac_volume_latch_out(dac_vol_latch),
  .dac_play_out(dac_play),
  .dac_reset_out(dac_reset),
  .msu_addr_out(msu_write_addr),
  .MSU_STATUS(msu_status_out),
  .msu_status_reset_out(msu_status_reset_bits),
  .msu_status_set_out(msu_status_set_bits),
  .msu_status_reset_we(msu_status_reset_we),
  .msu_volumerq(msu_volumerq_out),
  .msu_addressrq(msu_addressrq_out),
  .msu_trackrq(msu_trackrq_out),
  .msu_ptr_out(msu_ptr_addr),
  .msu_reset_out(msu_addr_reset),
  .bsx_regs_set_out(bsx_regs_set_bits),
  .bsx_regs_reset_out(bsx_regs_reset_bits),
  .bsx_regs_reset_we(bsx_regs_reset_we),
  .rtc_data_out(rtc_data_in),
  .rtc_pgm_we(rtc_pgm_we),
  .srtc_reset(srtc_reset),
  .dspx_pgm_data_out(dspx_pgm_data),
  .dspx_pgm_addr_out(dspx_pgm_addr),
  .dspx_pgm_we_out(dspx_pgm_we),
  .dspx_dat_data_out(dspx_dat_data),
  .dspx_dat_addr_out(dspx_dat_addr),
  .dspx_dat_we_out(dspx_dat_we),
  .dspx_reset_out(dspx_reset),
  .featurebits_out(featurebits),
  .mcu_rrq(MCU_RRQ),
  .mcu_wrq(MCU_WRQ),
  .mcu_rq_rdy(MCU_RDY),
  .region_out(mcu_region)
);

wire [7:0] DCM_STATUS;
// dcm1: dfs 4x
my_dcm snes_dcm(
  .CLKIN(CLKIN),
  .CLKFX(CLK2),
  .LOCKED(DCM_LOCKED),
  .RST(DCM_RST),
  .STATUS(DCM_STATUS)
);

my_dcm snes_dcm2(
  .CLKIN(SNES_SYSCLK),
  .CLKFX(SYSCLK2),
  .RST(DCM_RST)
);

assign DCM_RST=0;

reg [5:0] SNES_PARDr;
reg [5:0] SNES_READr;
reg [5:0] SNES_WRITEr;
reg [5:0] SNES_CPU_CLKr;

wire SNES_PARD_start = (SNES_PARDr == 6'b111110);
wire SNES_RD_start = (SNES_READr == 6'b111110);
wire SNES_WR_start = (SNES_WRITEr == 6'b111110);
wire SNES_cycle_start = (SNES_CPU_CLKr[5:0] == 6'b000001);
wire SNES_cycle_end = (SNES_CPU_CLKr[5:0] == 6'b111110);

always @(posedge SYSCLK2) begin
  SNES_PARDr <= {SNES_PARDr[4:0], SNES_PARD};
end

always @(posedge CLK2) begin
  SNES_READr <= {SNES_READr[4:0], SNES_READ};
  SNES_WRITEr <= {SNES_WRITEr[4:0], SNES_WRITE};
  SNES_CPU_CLKr <= {SNES_CPU_CLKr[4:0], SNES_CPU_CLK};
end

address snes_addr(
  .CLK(CLK2),
  .MAPPER(MAPPER),
  .featurebits(featurebits),
  .SNES_ADDR(SNES_ADDR), // requested address from SNES
  .SNES_PA(SNES_PA),
  .ROM_ADDR(MAPPED_SNES_ADDR),   // Address to request from SRAM (active low)
  .ROM_SEL(ROM_SEL),     // which SRAM unit to access
  .IS_SAVERAM(IS_SAVERAM),
  .IS_ROM(IS_ROM),
  .IS_WRITABLE(IS_WRITABLE),
  .SAVERAM_MASK(SAVERAM_MASK),
  .ROM_MASK(ROM_MASK),
  //MSU-1
  .msu_enable(msu_enable),
  //BS-X
  .use_bsx(use_bsx),
  .bsx_regs(bsx_regs),
  .bs_page_offset(bs_page_offset),
  .bs_page(bs_page),
  .bs_page_enable(bs_page_enable),
  //SRTC
  .srtc_enable(srtc_enable),
  //uPD77C25
  .dspx_enable(dspx_enable),
  .dspx_dp_enable(dspx_dp_enable),
  .dspx_a0(DSPX_A0),
  .r213f_enable(r213f_enable),
  .snescmd_rd_enable(snescmd_rd_enable),
  .snescmd_wr_enable(snescmd_wr_enable)
);

parameter MODE_SNES = 1'b0;
parameter MODE_MCU = 1'b1;

parameter ST_IDLE         = 18'b000000000000000001;
parameter ST_SNES_RD_ADDR = 18'b000000000000000010;
parameter ST_SNES_RD_WAIT = 18'b000000000000000100;
parameter ST_SNES_RD_END  = 18'b000000000000001000;
parameter ST_SNES_WR_ADDR = 18'b000000000000010000;
parameter ST_SNES_WR_WAIT1= 18'b000000000000100000;
parameter ST_SNES_WR_DATA = 18'b000000000001000000;
parameter ST_SNES_WR_WAIT2= 18'b000000000010000000;
parameter ST_SNES_WR_END  = 18'b000000000100000000;
parameter ST_MCU_RD_ADDR  = 18'b000000001000000000;
parameter ST_MCU_RD_WAIT  = 18'b000000010000000000;
parameter ST_MCU_RD_WAIT2 = 18'b000000100000000000;
parameter ST_MCU_RD_END   = 18'b000001000000000000;
parameter ST_MCU_WR_ADDR  = 18'b000010000000000000;
parameter ST_MCU_WR_WAIT  = 18'b000100000000000000;
parameter ST_MCU_WR_WAIT2 = 18'b001000000000000000;
parameter ST_MCU_WR_END   = 18'b010000000000000000;

parameter ROM_RD_WAIT = 4'h4;
parameter ROM_RD_WAIT_MCU = 4'h6;
parameter ROM_WR_WAIT1 = 4'h2;
parameter ROM_WR_WAIT2 = 4'h3;
parameter ROM_WR_WAIT_MCU = 4'h6;

reg [17:0] STATE;
initial STATE = ST_IDLE;

reg [7:0] SNES_DINr;
reg [7:0] ROM_DOUTr;

assign DSPX_SNES_DATA_IN = SNES_DATA;
assign SRTC_SNES_DATA_IN = SNES_DATA[3:0];
assign MSU_SNES_DATA_IN = SNES_DATA;
assign BSX_SNES_DATA_IN = bs_page_enable ? SNES_DINr : SNES_DATA;

reg [7:0] r213fr;
reg r213f_forceread;
reg [2:0] r213f_delay;
reg [1:0] r213f_state;
initial r213fr = 8'h55;
initial r213f_forceread = 0;
initial r213f_state = 2'b01;
initial r213f_delay = 3'b011;

reg[7:0] snescmd_regs[15:0];

assign SNES_DATA = (snescmd_rd_enable & ~SNES_PARD) ? snescmd_regs[SNES_ADDR[3:0]]
                   :(r213f_enable & ~SNES_PARD & ~r213f_forceread) ? r213fr
                   :(~SNES_READ ^ (r213f_forceread & r213f_enable & ~SNES_PARD))
                                ? (srtc_enable ? SRTC_SNES_DATA_OUT
                                  :dspx_enable ? DSPX_SNES_DATA_OUT
                                  :dspx_dp_enable ? DSPX_SNES_DATA_OUT
                                  :msu_enable ? MSU_SNES_DATA_OUT
                                  :bsx_data_ovr ? BSX_SNES_DATA_OUT
                                  :SNES_DINr /*(ROM_ADDR0 ? ROM_DATA[7:0] : ROM_DATA[15:8])*/) : 8'bZ;

reg [3:0] ST_MEM_DELAYr;
reg MCU_RD_PENDr;
reg MCU_WR_PENDr;
reg [23:0] ROM_ADDRr;
reg NEED_SNES_ADDRr;
always @(posedge CLK2) begin
  if(SNES_cycle_end) NEED_SNES_ADDRr <= 1'b1;
  else if(STATE & (ST_SNES_RD_END | ST_SNES_WR_END)) NEED_SNES_ADDRr <= 1'b0;
end

wire ASSERT_SNES_ADDR = SNES_CPU_CLK & NEED_SNES_ADDRr;

assign ROM_ADDR  = (SD_DMA_TO_ROM) ? MCU_ADDR[23:1] : (ASSERT_SNES_ADDR) ? MAPPED_SNES_ADDR[23:1] : ROM_ADDRr[23:1];
assign ROM_ADDR0 = (SD_DMA_TO_ROM) ? MCU_ADDR[0] : (ASSERT_SNES_ADDR) ? MAPPED_SNES_ADDR[0] : ROM_ADDRr[0];

reg ROM_WEr;
initial ROM_WEr = 1'b1;

reg RQ_MCU_RDYr;
initial RQ_MCU_RDYr = 1'b1;
assign MCU_RDY = RQ_MCU_RDYr;

always @(posedge CLK2) begin
  if(MCU_RRQ) begin
    MCU_RD_PENDr <= 1'b1;
    RQ_MCU_RDYr <= 1'b0;
  end else if(MCU_WRQ) begin
    MCU_WR_PENDr <= 1'b1;
    RQ_MCU_RDYr <= 1'b0;
  end else if(STATE & (ST_MCU_RD_END | ST_MCU_WR_END)) begin
    MCU_RD_PENDr <= 1'b0;
    MCU_WR_PENDr <= 1'b0;
    RQ_MCU_RDYr <= 1'b1;
  end
end

reg snes_wr_cycle;

always @(posedge CLK2) begin
  if(SNES_cycle_start & ~SNES_WR_start) begin
    STATE <= ST_SNES_RD_ADDR;
  end else if(SNES_WR_start) begin
    STATE <= ST_SNES_WR_ADDR;
  end else begin
    case(STATE)
	   ST_IDLE: begin
		  ROM_ADDRr <= MAPPED_SNES_ADDR;
		  if(MCU_RD_PENDr) STATE <= ST_MCU_RD_ADDR;
		  else if(MCU_WR_PENDr) STATE <= ST_MCU_WR_ADDR;
      else STATE <= ST_IDLE;
		end
		ST_SNES_RD_ADDR: begin
		  STATE <= ST_SNES_RD_WAIT;
		  ST_MEM_DELAYr <= ROM_RD_WAIT;
		end
		ST_SNES_RD_WAIT: begin
		  ST_MEM_DELAYr <= ST_MEM_DELAYr - 4'h1;
		  if(ST_MEM_DELAYr == 4'h0) STATE <= ST_SNES_RD_END;
		  else STATE <= ST_SNES_RD_WAIT;
		  if(ROM_ADDR0) SNES_DINr <= ROM_DATA[7:0];
		  else SNES_DINr <= ROM_DATA[15:8];
		end
		ST_SNES_RD_END: begin
		  STATE <= ST_IDLE;
		  if(ROM_ADDR0) SNES_DINr <= ROM_DATA[7:0];
		  else SNES_DINr <= ROM_DATA[15:8];
		end
      ST_SNES_WR_ADDR: begin
        ROM_WEr <= (!IS_FLASHWR & !IS_WRITABLE);
        snes_wr_cycle <= 1'b1;
		  STATE <= ST_SNES_WR_WAIT1;
		  ST_MEM_DELAYr <= ROM_WR_WAIT1;
		end
		ST_SNES_WR_WAIT1: begin
		  ST_MEM_DELAYr <= ST_MEM_DELAYr - 4'h1;
		  if(ST_MEM_DELAYr == 4'h0) STATE <= ST_SNES_WR_DATA;
		  else STATE <= ST_SNES_WR_WAIT1;
		end
		ST_SNES_WR_DATA: begin
        ROM_DOUTr <= SNES_DATA;
		  ST_MEM_DELAYr <= ROM_WR_WAIT2;
		  STATE <= ST_SNES_WR_WAIT2;
		end
      ST_SNES_WR_WAIT2: begin
		  ST_MEM_DELAYr <= ST_MEM_DELAYr - 4'h1;
		  if(ST_MEM_DELAYr == 4'h0) STATE <= ST_SNES_WR_END;
		  else STATE <= ST_SNES_WR_WAIT2;
		end
		ST_SNES_WR_END: begin
		  STATE <= ST_IDLE;
		  ROM_WEr <= 1'b1;
		  snes_wr_cycle <= 1'b0;
		end
		ST_MCU_RD_ADDR: begin
		  ROM_ADDRr <= MCU_ADDR;
		  STATE <= ST_MCU_RD_WAIT;
		  ST_MEM_DELAYr <= ROM_RD_WAIT_MCU;
		end
		ST_MCU_RD_WAIT: begin
		  ST_MEM_DELAYr <= ST_MEM_DELAYr - 4'h1;
		  if(ST_MEM_DELAYr == 4'h0) begin
		    STATE <= ST_MCU_RD_WAIT2;
			 ST_MEM_DELAYr <= 4'h2;
		  end
		  else STATE <= ST_MCU_RD_WAIT;
		  if(ROM_ADDR0) MCU_DINr <= ROM_DATA[7:0];
		  else MCU_DINr <= ROM_DATA[15:8];
      end
		ST_MCU_RD_WAIT2: begin
		  ST_MEM_DELAYr <= ST_MEM_DELAYr - 4'h1;
		  if(ST_MEM_DELAYr == 4'h0) begin
		    STATE <= ST_MCU_RD_END;
		  end else STATE <= ST_MCU_RD_WAIT2;
		end
		ST_MCU_RD_END: begin
		  STATE <= ST_IDLE;
		end
		ST_MCU_WR_ADDR: begin
		  ROM_ADDRr <= MCU_ADDR;
		  STATE <= ST_MCU_WR_WAIT;
		  ST_MEM_DELAYr <= ROM_WR_WAIT_MCU;
		  ROM_DOUTr <= MCU_DOUT;
		  ROM_WEr <= 1'b0;
		end
		ST_MCU_WR_WAIT: begin
		  ST_MEM_DELAYr <= ST_MEM_DELAYr - 4'h1;
		  if(ST_MEM_DELAYr == 4'h0) begin
          ROM_WEr <= 1'b1;
		    STATE <= ST_MCU_WR_WAIT2;
			 ST_MEM_DELAYr <= 4'h2;
		  end
		  else STATE <= ST_MCU_WR_WAIT;
      end
		ST_MCU_WR_WAIT2: begin
		  ST_MEM_DELAYr <= ST_MEM_DELAYr - 4'h1;
		  if(ST_MEM_DELAYr == 4'h0) begin
		    STATE <= ST_MCU_WR_END;
        end else STATE <= ST_MCU_WR_WAIT2;
		end
		ST_MCU_WR_END: begin
		  STATE <= ST_IDLE;
		end

    endcase
  end
end

always @(posedge SYSCLK2) begin
  if(SNES_PARD_start & r213f_enable) begin
    r213f_forceread <= 1'b1;
    r213f_delay <= 3'b001;
    r213f_state <= 2'b10;
  end else if(r213f_state == 2'b10) begin
    r213f_delay <= r213f_delay - 1;
    if(r213f_delay == 3'b000) begin
      r213f_forceread <= 1'b0;
      r213f_state <= 2'b01;
      r213fr <= {SNES_DATA[7:5], mcu_region, SNES_DATA[3:0]};
    end
  end
end

always @(posedge CLK2) begin
  if(SNES_WR_end & snescmd_wr_enable) begin
    snescmd_regs[SNES_ADDR[3:0]] <= SNES_DATA;
  end
end

reg ROM_WE_1;
reg MCU_WRITE_1;

always @(posedge CLK2) begin
  ROM_WE_1 <= ROM_WE;
  MCU_WRITE_1<= MCU_WRITE;
end

assign ROM_DATA[7:0] = ROM_ADDR0
                       ?(SD_DMA_TO_ROM ? (!MCU_WRITE_1 ? MCU_DOUT : 8'bZ)
							                   /*: ((~SNES_WRITE & (IS_WRITABLE | IS_FLASHWR)) ? SNES_DATA */
                                        : (ROM_DOUT_ENr ? ROM_DOUTr : 8'bZ) //)
                        )
                       :8'bZ;

assign ROM_DATA[15:8] = ROM_ADDR0 ? 8'bZ
                        :(SD_DMA_TO_ROM ? (!MCU_WRITE_1 ? MCU_DOUT : 8'bZ)
								                 /*:  ((~SNES_WRITE & (IS_WRITABLE | IS_FLASHWR)) ? SNES_DATA */
                                         : (ROM_DOUT_ENr ? ROM_DOUTr : 8'bZ) //)
                         );

assign ROM_WE = SD_DMA_TO_ROM
                ?MCU_WRITE
                :/*(SNES_FAKE_CLK & (IS_WRITABLE | IS_FLASHWR)) ? SNES_WRITE :*/ ROM_WEr;

// OE always active. Overridden by WE when needed.
assign ROM_OE = 1'b0;

assign ROM_CE = 1'b0;

assign ROM_BHE = /*(~SD_DMA_TO_ROM & ~ROM_WE & ~ROM_SA) ?*/ ROM_ADDR0 /*: 1'b0*/;
assign ROM_BLE = /*(~SD_DMA_TO_ROM & ~ROM_WE & ~ROM_SA) ?*/ !ROM_ADDR0 /*: 1'b0*/;

assign SNES_DATABUS_OE = (dspx_enable | dspx_dp_enable) ? 1'b0 :
                         msu_enable ? 1'b0 :
                         bsx_data_ovr ? (SNES_READ & SNES_WRITE) :
                         srtc_enable ? (SNES_READ & SNES_WRITE) :
								 bs_page_enable ? (SNES_READ) :
                         r213f_enable & !SNES_PARD ? 1'b0 :
                         ((IS_ROM & SNES_CS)
                          |(!IS_ROM & !IS_SAVERAM & !IS_WRITABLE & !IS_FLASHWR)
                          |(SNES_READ & SNES_WRITE)
                         );

assign SNES_DATABUS_DIR = (!SNES_READ | (!SNES_PARD & r213f_enable))
                           ? 1'b1 ^ r213f_forceread
                           : 1'b0;

assign IRQ_DIR = 1'b0;
assign SNES_IRQ = 1'bZ;

assign p113_out = 1'b0;

endmodule
