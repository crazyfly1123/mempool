// Copyright 2021 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51

`include "common_cells/registers.svh"

module ctrl_registers
  import mempool_pkg::ro_cache_ctrl_t;
#(
  parameter int DataWidth                      = 32,
  parameter int NumRegs                        = 0,
  // Parameters
  parameter logic [DataWidth-1:0] TCDMBaseAddr = 0,
  parameter logic [DataWidth-1:0] TCDMSize     = 0,
  parameter logic [DataWidth-1:0] NumCores     = 0,
  // AXI Structs
  parameter type axi_lite_req_t                = logic,
  parameter type axi_lite_resp_t               = logic
) (
  input  logic                           clk_i,
  input  logic                           rst_ni,
  // AXI Bus
  input  axi_lite_req_t                  axi_lite_slave_req_i,
  output axi_lite_resp_t                 axi_lite_slave_resp_o,
  // Control registers
  output logic      [DataWidth-1:0]      eoc_o,
  output logic                           eoc_valid_o,
  output logic      [NumCores-1:0]       wake_up_o,
  output logic      [DataWidth-1:0]      tcdm_start_address_o,
  output logic      [DataWidth-1:0]      tcdm_end_address_o,
  output logic      [DataWidth-1:0]      num_cores_o,
  output ro_cache_ctrl_t                 ro_cache_ctrl_o
);

  import mempool_pkg::*;

  /*****************
   *  Definitions  *
   *****************/

  localparam int unsigned DataWidthInBytes = (DataWidth + 7) / 8;
  localparam int unsigned RegNumBytes      = NumRegs * DataWidthInBytes;
  localparam int unsigned RegDataWidth     = NumRegs * DataWidth;

  localparam logic [DataWidthInBytes-1:0] ReadOnlyReg  = {DataWidthInBytes{1'b1}};
  localparam logic [DataWidthInBytes-1:0] ReadWriteReg = {DataWidthInBytes{1'b0}};

  // Memory map
  // [3:0]:  eoc_reg                        (rw)
  // [7:4]:  wake_up_reg                    (rw)
  // [11:8]: tcdm_start_adress_reg          (ro)
  // [15:12]:tcdm_end_address_reg           (ro)
  // [19:16]:nr_cores_address_reg           (ro)
  // [23:20]:ro_cache_enable                (rw)
  // [27:24]:ro_cache_flush                 (rw)
  // [31:28]:ro_cache_start_0               (rw)
  // [35:32]:ro_cache_end_0                 (rw)
  // [39:36]:ro_cache_start_1               (rw)
  // [43:40]:ro_cache_end_1                 (rw)
  // [47:44]:ro_cache_start_2               (rw)
  // [51:48]:ro_cache_end_2                 (rw)
  // [55:52]:ro_cache_start_3               (rw)
  // [59:56]:ro_cache_end_3                 (rw)
  localparam logic [NumRegs-1:0][DataWidth-1:0] RegRstVal = '{
    32'h0000_0010,
    32'h0000_000C,
    32'h0000_000C,
    32'h0000_0008,
    32'hA000_1000,
    32'hA000_0000,
    32'h8000_1000,
    32'h8000_0000,
    {DataWidth{1'b0}},
    32'h1,
    NumCores,
    TCDMBaseAddr + TCDMSize,
    TCDMBaseAddr,
    {DataWidth{1'b0}},
    {DataWidth{1'b0}}
  };
  localparam logic [NumRegs-1:0][DataWidthInBytes-1:0] AxiReadOnly = '{
    ReadWriteReg,
    ReadWriteReg,
    ReadWriteReg,
    ReadWriteReg,
    ReadWriteReg,
    ReadWriteReg,
    ReadWriteReg,
    ReadWriteReg,
    ReadWriteReg,
    ReadWriteReg,
    ReadOnlyReg,
    ReadOnlyReg,
    ReadOnlyReg,
    ReadWriteReg,
    ReadWriteReg
  };

  /***************
   *  Registers  *
   ***************/
  logic [DataWidth-1:0]   eoc;
  logic [DataWidth-1:0]   wake_up;
  logic [DataWidth-1:0]   tcdm_start_address;
  logic [DataWidth-1:0]   tcdm_end_address;
  logic [DataWidth-1:0]   num_cores;
  logic [DataWidth-1:0]   ro_cache_enable;
  logic [DataWidth-1:0]   ro_cache_flush;
  logic [DataWidth-1:0]   ro_cache_start_0;
  logic [DataWidth-1:0]   ro_cache_end_0;
  logic [DataWidth-1:0]   ro_cache_start_1;
  logic [DataWidth-1:0]   ro_cache_end_1;
  logic [DataWidth-1:0]   ro_cache_start_2;
  logic [DataWidth-1:0]   ro_cache_end_2;
  logic [DataWidth-1:0]   ro_cache_start_3;
  logic [DataWidth-1:0]   ro_cache_end_3;

  logic [RegNumBytes-1:0] wr_active_d;
  logic [RegNumBytes-1:0] wr_active_q;

  axi_lite_regs #(
    .RegNumBytes (RegNumBytes               ),
    .AxiAddrWidth(AddrWidth                 ),
    .AxiDataWidth(AxiLiteDataWidth          ),
    .AxiReadOnly (AxiReadOnly               ),
    .RegRstVal   (RegRstVal                 ),
    .req_lite_t  (axi_lite_req_t            ),
    .resp_lite_t (axi_lite_resp_t           )
  ) i_axi_lite_regs (
    .clk_i      (clk_i                                                          ),
    .rst_ni     (rst_ni                                                         ),
    .axi_req_i  (axi_lite_slave_req_i                                           ),
    .axi_resp_o (axi_lite_slave_resp_o                                          ),
    .wr_active_o(wr_active_d                                                    ),
    .rd_active_o(/* Unused */                                                   ),
    .reg_d_i    ('0                                                             ),
    .reg_load_i ('0                                                             ),
    .reg_q_o    ({ro_cache_end_3, ro_cache_start_3, ro_cache_end_2, ro_cache_start_2,
                  ro_cache_end_1, ro_cache_start_1, ro_cache_end_0, ro_cache_start_0,
                  ro_cache_flush, ro_cache_enable,
                  num_cores, tcdm_end_address, tcdm_start_address, wake_up, eoc})
  );

  /***************
   *   Signals   *
   ***************/

  assign eoc_o                = eoc >> 1;
  assign tcdm_start_address_o = tcdm_start_address;
  assign tcdm_end_address_o   = tcdm_end_address;
  assign num_cores_o          = num_cores;

  assign ro_cache_ctrl_o.enable        = ro_cache_enable[0];
  assign ro_cache_ctrl_o.flush_valid   = ro_cache_flush[0];
  assign ro_cache_ctrl_o.start_addr[0] = ro_cache_start_0;
  assign ro_cache_ctrl_o.start_addr[1] = ro_cache_start_1;
  assign ro_cache_ctrl_o.start_addr[2] = ro_cache_start_2;
  assign ro_cache_ctrl_o.start_addr[3] = ro_cache_start_3;
  assign ro_cache_ctrl_o.end_addr[0]   = ro_cache_end_0;
  assign ro_cache_ctrl_o.end_addr[1]   = ro_cache_end_1;
  assign ro_cache_ctrl_o.end_addr[2]   = ro_cache_end_2;
  assign ro_cache_ctrl_o.end_addr[3]   = ro_cache_end_3;

  // converts 32 bit wake up to 256 bit
  always_comb begin
    wake_up_o = '0;
    if (wr_active_q[7:4]) begin
      if (wake_up < NumCores) begin
        wake_up_o = 1 << wake_up;
      end else if (wake_up == {DataWidth{1'b1}}) begin
        wake_up_o = {NumCores{1'b1}};
      end
    end
  end

  assign eoc_valid_o = eoc[0];

  // register to add +1 latency to the wr_active signal
  `FF(wr_active_q, wr_active_d, '0, clk_i, rst_ni)

endmodule : ctrl_registers
