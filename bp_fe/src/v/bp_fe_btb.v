/*
 * bp_fe_btb.v
 * 
 * Branch Target Buffer (BTB) stores the addresses of the branch targets and the
 * corresponding branch sites. Branch happens from the branch sites to the branch
 * targets. In order to save the logic sizes, the BTB is designed to have limited 
 * entries for storing the branch sites, branch target pairs. The implementation 
 * uses the bsg_mem_1rw_sync_synth RAM design.
 *
 * Notes:
 *   BTB writes are prioritized over BTB reads, since they come on redirections and therefore 
 *     the BTB read is most likely for an erroneous instruction, anyway.
 */
module bp_fe_btb
 import bp_fe_pkg::*;
 import bp_common_rv64_pkg::*;
 #(parameter vaddr_width_p = "inv"
   , parameter btb_tag_width_p = "inv"
   , parameter btb_idx_width_p = "inv"

   , localparam btb_offset_width_lp = 2 // bottom 2 bits are unused without compressed branches
                                        // TODO: Should be a parameterizable struct
   ) 
  (input                          clk_i
   , input                        reset_i 

   // Synchronous read
   , input [vaddr_width_p-1:0]    r_addr_i
   , input                        r_v_i
   , output [vaddr_width_p-1:0]   br_tgt_o
   , output                       br_tgt_v_o

   , input                        w_set_i
   , input                        w_clear_i
   , input [btb_tag_width_p-1:0]  w_tag_i
   , input [btb_idx_width_p-1:0]  w_idx_i
   , input [vaddr_width_p-1:0]    br_tgt_i
   );

localparam btb_els_lp = 2**btb_idx_width_p;

logic [btb_tag_width_p-1:0] tag_mem_li, tag_mem_lo;
logic [btb_idx_width_p-1:0] tag_mem_addr_li;
logic                       tag_mem_v_lo;

logic [vaddr_width_p-1:0]   tgt_mem_li, tgt_mem_lo;
logic [btb_idx_width_p-1:0] tgt_mem_addr_li;
   
logic [btb_tag_width_p-1:0] w_tag_n, w_tag_r;
logic [btb_tag_width_p-1:0] r_tag_n, r_tag_r;
logic [btb_idx_width_p-1:0] r_idx_n, r_idx_r;
logic                       r_v_r;

assign tag_mem_li      = w_tag_i; 
assign tgt_mem_li      = br_tgt_i[0+:vaddr_width_p];
                            
logic [btb_els_lp-1:0] v_r, v_n;
    
bsg_mem_1r1w_sync
 #(.width_p(btb_tag_width_p+vaddr_width_p)
   ,.els_p(btb_els_lp)
   )
 tag_mem
  (.clk_i(clk_i)
   ,.reset_i(reset_i)
 

   ,.w_v_i(w_set_i)
   ,.w_addr_i(w_idx_i)
   ,.w_data_i({tag_mem_li, tgt_mem_li})

   ,.r_v_i(r_v_i)
   ,.r_addr_i(r_addr_i[btb_offset_width_lp+:btb_idx_width_p])
   ,.r_data_o({tag_mem_lo, tgt_mem_lo})
   );


assign tag_mem_v_lo = v_r[r_idx_r];
assign br_tgt_o   = tgt_mem_lo;
assign br_tgt_v_o = tag_mem_v_lo & r_v_r & (tag_mem_lo == r_tag_r);

always_ff @(posedge clk_i)
  begin
    if (reset_i)
      begin
        r_v_r <= '0;
        r_tag_r <= '0;
        r_idx_r <= '0;
      end
    else
      begin
        // Read didn't actually happen if there was a write
        r_v_r <= r_v_i;
        r_tag_r <= r_addr_i[btb_offset_width_lp+btb_idx_width_p+:btb_tag_width_p];
        r_idx_r <= r_addr_i[btb_offset_width_lp+:btb_idx_width_p];
      end
    
      if (reset_i)
        v_r <= '0;
      else if (w_set_i)
        v_r[w_idx_i] <= 1'b1;
      else  if (w_clear_i)
        v_r[w_idx_i] <= 1'b0;
      else
        v_r <= v_r;
  end

always_ff @(posedge clk_i)
  begin
//    if (w_v_i)
//      begin
//        $display("[BTB] WRITE INDEX: %x TAG: %x TARGET: %x"
//                 , tag_mem_addr_li
//                 , tag_mem_li
//                 , tgt_mem_li
//                 );
//      end
//    if (br_tgt_v_o)
//      begin
//        $display("[BTB] READ INDEX: %x TAG: %x TARGET: %x"
//                 , r_idx_r
//                 , r_tag_r
//                 , br_tgt_o
//                 );
//      end
  end

endmodule
