
module bp_lite_to_stream
 import bp_common_pkg::*;
 import bp_common_aviary_pkg::*;
 import bp_me_pkg::*;
 #(parameter bp_params_e bp_params_p = e_bp_default_cfg
   `declare_bp_proc_params(bp_params_p)

   , parameter in_data_width_p  = "inv"
   , parameter out_data_width_p = "inv"

   , parameter logic master_p = 0

   `declare_bp_mem_if_widths(paddr_width_p, in_data_width_p, lce_id_width_p, lce_assoc_p, in_mem)
   `declare_bp_mem_if_widths(paddr_width_p, out_data_width_p, lce_id_width_p, lce_assoc_p, out_mem)
   )
  (input                                            clk_i
   , input                                          reset_i

   // Master BP Lite
   , input [in_mem_msg_width_lp-1:0]                mem_i
   , input                                          mem_v_i
   , output logic                                   mem_ready_o

   // Client BP Stream
   , output logic [out_mem_msg_header_width_lp-1:0] mem_header_o
   , output logic [out_data_width_p-1:0]            mem_data_o
   , output logic                                   mem_v_o
   , input                                          mem_yumi_i
   , output logic                                   mem_lock_o
   );

  `declare_bp_mem_if(paddr_width_p, cce_block_width_p, lce_id_width_p, lce_assoc_p, in_mem);
  `declare_bp_mem_if(paddr_width_p, cce_block_width_p, lce_id_width_p, lce_assoc_p, out_mem);
  bp_in_mem_msg_s mem_cast_i;
  assign mem_cast_i = mem_i;

  localparam in_data_bytes_lp = in_data_width_p/8;
  localparam out_data_bytes_lp = out_data_width_p/8;
  localparam stream_words_lp = in_data_width_p/out_data_width_p;
  localparam data_ptr_width_lp = `BSG_SAFE_CLOG2(stream_words_lp);
  localparam stream_offset_width_lp = `BSG_SAFE_CLOG2(out_data_bytes_lp);

  bp_in_mem_msg_header_s header_lo;
  logic mem_v_lo, mem_yumi_li;
  bsg_one_fifo
   #(.width_p($bits(bp_in_mem_msg_header_s)))
   header_fifo
    (.clk_i(clk_i)
     ,.reset_i(reset_i)

     ,.data_i(mem_cast_i.header)
     ,.v_i(mem_v_i)
     ,.ready_o(mem_ready_o)

     ,.data_o(header_lo)
     ,.v_o(mem_v_lo)
     ,.yumi_i(mem_yumi_li)
     );

  wire is_wr = mem_cast_i.header.msg_type inside {e_mem_msg_uc_wr, e_mem_msg_wr};
  wire [data_ptr_width_lp-1:0] num_stream_cmds = (master_p ^ is_wr)
    ? 1'b1
    : `BSG_MAX(((1'b1 << mem_cast_i.header.size) / out_data_bytes_lp), 1'b1);
  logic [out_data_width_p-1:0] data_lo;
  logic data_v_lo, data_yumi_li;
  bsg_parallel_in_serial_out_dynamic
   #(.width_p(in_data_width_p), .max_els_p(stream_words_lp))
   piso
    (.clk_i(clk_i)
     ,.reset_i(reset_i)

     ,.v_i(mem_v_i)
     ,.len_i(num_stream_cmds)
     ,.data_i(mem_cast_i.data)

     ,.data_o(data_lo)
     ,.v_o(data_v_lo)
     ,.yumi_i(data_yumi_li)

     // We rely on the header fifo to handle ready/valid handshaking
     ,.len_v_o(/* Unused */)
     ,.ready_o(/* Unused */)
     );

  // We wouldn't need this counter if we could peek into the PISO...
  logic [data_ptr_width_lp-1:0] data_cnt;
  bsg_counter_clear_up
   #(.max_val_p(stream_words_lp), .init_val_p(0))
   data_counter
    (.clk_i(clk_i)
     ,.reset_i(reset_i)

     ,.clear_i(mem_v_i)
     ,.up_i(data_yumi_li)
     ,.count_o(data_cnt)
     );
  wire last_data = (data_cnt == (num_stream_cmds-1'b1));

  bp_out_mem_msg_header_s mem_header_cast_o;
  assign mem_header_o = mem_header_cast_o;
  always_comb
    begin
      // Autoincrement address
      mem_header_cast_o = header_lo;
      mem_header_cast_o.addr = header_lo.addr + (data_cnt << stream_offset_width_lp);
    end
  assign mem_data_o = data_lo;
  assign mem_v_o = mem_v_lo;
  assign mem_yumi_li = last_data & mem_yumi_i;
  assign mem_lock_o = mem_v_o;

  //synopsys translate_off
  initial
    begin
      assert (in_data_width_p >= out_data_width_p)
        else $error("Master data cannot be smaller than client");
      assert (in_data_width_p % out_data_width_p)
        else $error("Master data must be a multiple of client data");
    end
  //synopsys translate_on

endmodule

