/**
 *
 * Name:
 *   bp_cce_dir.v
 *
 * Description:
 *   The directory stores the coherence state and tags for all cache blocks tracked by
 *   a CCE. The directory supports a small set of operations such as reading and writing
 *   pending bits for a way-group, reading a way-group or entry, and writing an entry's
 *   coherence state and tag.
 *
 *   The way-group memory in the directory is a synchronous read 1RW memories.
 *   The pending bits are stored in flops and may be read asynchronously.
 *
 *   All writes take 1 cycle
 *   RDW and RDE instructions present valid data in the next cycle (synchronous reads)
 *   RDP presents valid data in same cycle (asynchronous reads)
 *
 */

module bp_cce_dir
  import bp_common_pkg::*;
  import bp_cce_pkg::*;
  #(parameter num_way_groups_p            = "inv"
    , parameter num_lce_p                 = "inv"
    , parameter num_cce_p                 = "inv"
    , parameter lce_assoc_p               = "inv"
    , parameter tag_width_p               = "inv"

    // Derived parameters
    , localparam lg_num_way_groups_lp     = `BSG_SAFE_CLOG2(num_way_groups_p)
    , localparam lg_num_lce_lp            = `BSG_SAFE_CLOG2(num_lce_p)
    , localparam lg_lce_assoc_lp          = `BSG_SAFE_CLOG2(lce_assoc_p)

    // Directory information widths
    , localparam entry_width_lp           = (tag_width_p+`bp_cce_coh_bits)
    , localparam tag_set_width_lp         = (entry_width_lp*lce_assoc_p)

    // TODO: tag sets per row could be an input parameter
    // 1 LCE : 1 tag set per row
    // 2, 4, 8, 16 LCE : 2 tag sets per row
    , localparam dir_tag_sets_per_row_lp  = (num_lce_p / num_cce_p)
    , localparam lg_dir_tag_sets_per_row_lp = `BSG_SAFE_CLOG2(dir_tag_sets_per_row_lp)
    // Width of each directory RAM row
    , localparam dir_row_width_lp         = (tag_set_width_lp*dir_tag_sets_per_row_lp)
    // number of entry (tag+state) per directory row
    , localparam dir_entry_per_row_lp     = (dir_tag_sets_per_row_lp*lce_assoc_p)

    // Number of rows in directory required to hold a complete tag set
    // 1, 2 LCE: 1
    // 4 LCE: 2
    // 8 LCE: 4
    // 16 LCE: 8
    , localparam dir_rows_per_wg_lp       = (num_lce_p / dir_tag_sets_per_row_lp)
    , localparam lg_dir_rows_per_wg_lp    = `BSG_SAFE_CLOG2(dir_rows_per_wg_lp)
    // Total number of rows in the directory RAM
    , localparam dir_rows_lp              = (dir_rows_per_wg_lp*num_way_groups_p)
    , localparam lg_dir_rows_lp           = `BSG_SAFE_CLOG2(dir_rows_lp)

    , localparam sh_assign_shift_lp = (dir_tag_sets_per_row_lp == 1) ? 0 : lg_dir_tag_sets_per_row_lp

  )
  (input                                                          clk_i
   , input                                                        reset_i

   , input [lg_num_way_groups_lp-1:0]                             way_group_i
   , input [lg_num_lce_lp-1:0]                                    lce_i
   , input [lg_lce_assoc_lp-1:0]                                  way_i
   , input [lg_lce_assoc_lp-1:0]                                  lru_way_i
   , input [`bp_cce_inst_minor_op_width-1:0]                      r_cmd_i
   , input                                                        r_v_i

   , input [tag_width_p-1:0]                                      tag_i
   , input [`bp_cce_coh_bits-1:0]                                 coh_state_i
   , input                                                        pending_i
   , input [`bp_cce_inst_minor_op_width-1:0]                      w_cmd_i
   , input                                                        w_v_i

   , output logic                                                 pending_o
   , output logic                                                 pending_v_o

   , output logic                                                 done_o

   , output logic                                                 sharers_v_o
   , output logic [num_lce_p-1:0]                                 sharers_hits_o
   , output logic [num_lce_p-1:0][lg_lce_assoc_lp-1:0]            sharers_ways_o
   , output logic [num_lce_p-1:0][`bp_cce_coh_bits-1:0]           sharers_coh_states_o

   , output logic                                                 lru_v_o
   , output logic                                                 lru_cached_excl_o
   , output logic [tag_width_p-1:0]                               lru_tag_o

  );

  typedef struct packed {
    logic [tag_width_p-1:0]      tag;
    logic [`bp_cce_coh_bits-1:0] state;
  } dir_entry_s;

  // pending bits
  logic [num_way_groups_p-1:0] pending_bits_r, pending_bits_n;
  logic pending_w_v, pending_r_v;
  assign pending_w_v = w_v_i & (w_cmd_i == e_wdp_op);
  assign pending_r_v = r_v_i & (r_cmd_i == e_rdp_op);

  always_ff @(posedge clk_i) begin
    if (reset_i) begin
      pending_bits_r <= '0;
    end else begin
      pending_bits_r <= pending_bits_n;
    end
  end

  always_comb begin
    if (reset_i) begin
      pending_bits_n = '0;
    end else begin
      pending_bits_n = pending_bits_r;
      if (pending_w_v) begin
        pending_bits_n[way_group_i] = pending_i;
      end
    end
  end

  assign pending_o = pending_bits_r[way_group_i];
  assign pending_v_o = pending_r_v;

  // Directory

  // read / write valid signals
  logic dir_ram_w_v, dir_ram_r_v;
  logic dir_ram_v;
  // read / write address
  logic [lg_dir_rows_lp-1:0] dir_ram_addr;
  // write mask and data in
  logic [dir_row_width_lp-1:0] dir_ram_w_mask;
  logic [dir_row_width_lp-1:0] dir_ram_w_data;
  // data out
  dir_entry_s [dir_entry_per_row_lp-1:0] dir_row_lo;
  dir_entry_s [dir_tag_sets_per_row_lp-1:0][lce_assoc_p-1:0] dir_row_entries;
  assign dir_row_entries = dir_row_lo;

  logic [lg_dir_tag_sets_per_row_lp-1:0] tag_set_select;

  typedef enum logic [2:0] {
    RESET
    ,READY
    ,READ
    ,FINISH_READ
  } dir_state_e;

  dir_state_e dir_state, dir_state_n;

  logic [lg_dir_rows_per_wg_lp-1:0] dir_rd_cnt_r, dir_rd_cnt_n;
  logic [lg_num_way_groups_lp-1:0]  way_group_r, way_group_n;
  logic [lg_num_lce_lp-1:0]         lce_r, lce_n;
  logic [lg_lce_assoc_lp-1:0]       way_r, way_n;
  logic [lg_lce_assoc_lp-1:0]       lru_way_r, lru_way_n;
  logic [tag_width_p-1:0]           tag_r, tag_n;
  logic dir_rd_v_r, dir_rd_v_n;

  logic [num_lce_p-1:0]                                 sharers_hits_r, sharers_hits_n;
  logic [num_lce_p-1:0][lg_lce_assoc_lp-1:0]            sharers_ways_r, sharers_ways_n;
  logic [num_lce_p-1:0][`bp_cce_coh_bits-1:0]           sharers_coh_states_r, sharers_coh_states_n;

  assign sharers_hits_o = sharers_hits_r;
  assign sharers_ways_o = sharers_ways_r;
  assign sharers_coh_states_o = sharers_coh_states_r;

  logic [dir_tag_sets_per_row_lp-1:0]                                 sharers_hits;
  logic [dir_tag_sets_per_row_lp-1:0][lg_lce_assoc_lp-1:0]            sharers_ways;
  logic [dir_tag_sets_per_row_lp-1:0][`bp_cce_coh_bits-1:0]           sharers_coh_states;

  always_ff @(posedge clk_i) begin
    if (reset_i) begin
      dir_state <= RESET;
      dir_rd_cnt_r <= '0;
      way_group_r <= '0;
      lce_r <= '0;
      way_r <= '0;
      lru_way_r <= '0;
      tag_r <= '0;
      dir_rd_v_r <= '0;

      sharers_hits_r <= '0;
      sharers_ways_r <= '0;
      sharers_coh_states_r <= '0;

    end else begin
      dir_state <= dir_state_n;
      dir_rd_cnt_r <= dir_rd_cnt_n;
      way_group_r <= way_group_n;
      lce_r <= lce_n;
      way_r <= way_n;
      lru_way_r <= lru_way_n;
      tag_r <= tag_n;
      dir_rd_v_r <= dir_rd_v_n;

      sharers_hits_r <= sharers_hits_n;
      sharers_ways_r <= sharers_ways_n;
      sharers_coh_states_r <= sharers_coh_states_n;

    end
  end

  // Directory State Machine logic
  always_comb begin
    if (reset_i) begin
      dir_state_n = RESET;
      dir_rd_cnt_n = '0;
      dir_ram_w_mask = '0;
      dir_ram_w_data = '0;
      dir_ram_v = '0;
      dir_ram_r_v = '0;
      dir_ram_w_v = '0;
      way_group_n = '0;
      lce_n = '0;
      way_n = '0;
      lru_way_n = '0;
      tag_n = '0;
      dir_rd_v_n = '0;

      done_o = '0;
      sharers_v_o = '0;

      sharers_hits_n = '0;
      sharers_ways_n = '0;
      sharers_coh_states_n = '0;

      tag_set_select = '0;

    end else begin
      // hold state by default
      dir_state_n = dir_state;
      dir_rd_cnt_n = '0;
      dir_ram_w_mask = '0;
      dir_ram_w_data = '0;
      dir_ram_v = '0;
      dir_ram_r_v = '0;
      dir_ram_w_v = '0;
      way_group_n = way_group_r;
      lce_n = lce_r;
      way_n = way_r;
      lru_way_n = lru_way_r;
      tag_n = tag_r;
      dir_rd_v_n = '0;

      done_o = '0;
      sharers_v_o = '0;

      sharers_hits_n = sharers_hits_r;
      sharers_ways_n = sharers_ways_r;
      sharers_coh_states_n = sharers_coh_states_r;

      tag_set_select = '0;

      case (dir_state)
        RESET: begin
          dir_state_n = (reset_i) ? RESET : READY;
        end
        READY: begin
          dir_state_n = READY;
          // TODO: RDE not supported at the moment

          // initiate directory read of first row of way group
          // first row will be valid on output of directory next cycle (in READ)
          if (r_v_i & (r_cmd_i == e_rdw_op)) begin
            dir_state_n = READ;
            way_group_n = way_group_i;
            lce_n = lce_i;
            way_n = way_i;
            lru_way_n = lru_way_i;
            tag_n = tag_i;
            dir_ram_r_v = 1'b1;
            dir_ram_v = 1'b1;
            dir_ram_addr = (dir_rows_per_wg_lp == 1) ? way_group_i : {way_group_i, dir_rd_cnt_r};
            dir_rd_cnt_n = '0;
            dir_rd_v_n = 1'b1;

            // reset the sharers vectors for the new read
            sharers_hits_n = '0;
            sharers_ways_n = '0;
            sharers_coh_states_n = '0;

          // directory write
          end else if (w_v_i & ((w_cmd_i == e_wde_op) | (w_cmd_i == e_wds_op))) begin
            dir_state_n = READY;
            dir_ram_v = 1'b1;
            dir_ram_w_v = 1'b1;

            tag_set_select = (num_lce_p == 1) ? '0 : lce_i[0+:lg_dir_tag_sets_per_row_lp];
            dir_ram_addr = (dir_rows_per_wg_lp == 1) ? way_group_i : {way_group_i, tag_set_select};

            if (w_cmd_i == e_wde_op) begin
              dir_ram_w_mask = {{(dir_row_width_lp-entry_width_lp){1'b0}},{entry_width_lp{1'b1}}}
                              << (tag_set_select*tag_set_width_lp + way_i*entry_width_lp);
            end else if (w_cmd_i == e_wds_op) begin
              dir_ram_w_mask = {{(dir_row_width_lp-`bp_cce_coh_bits){1'b0}},{`bp_cce_coh_bits{1'b1}}}
                              << (tag_set_select*tag_set_width_lp + way_i*entry_width_lp);
            end else begin
              dir_ram_w_mask = '0;
            end

            dir_ram_w_data = {{(dir_row_width_lp-entry_width_lp){1'b0}},{tag_i, coh_state_i}}
                             << (tag_set_select*tag_set_width_lp + way_i*entry_width_lp);
          end
        end
        READ: begin

          for(int i = 0; i < dir_tag_sets_per_row_lp; i++) begin
            sharers_hits_n[(dir_rd_cnt_r << sh_assign_shift_lp) + i] = sharers_ways[i];
            sharers_ways_n[(dir_rd_cnt_r << sh_assign_shift_lp) + i] = sharers_ways[i];
            sharers_coh_states_n[(dir_rd_cnt_r << sh_assign_shift_lp) + i] = sharers_coh_states[i];
          end

          dir_rd_cnt_n = dir_rd_cnt_r + 'd1;

          // do another read if required
          // This only happens if there is more than 1 LCE, so dir_ram_addr doesn't need to check
          // whether there is only 1 LCE, as it does in the READY state
          if (dir_rd_cnt_r < (dir_rows_per_wg_lp-1)) begin
            dir_ram_r_v = 1'b1;
            dir_ram_v = 1'b1;
            dir_ram_addr = {way_group_r, dir_rd_cnt_r};
            dir_rd_v_n = 1'b1;
            dir_state_n = READ;
          end else begin
            dir_state_n = FINISH_READ;
          end
        end
        FINISH_READ: begin
          // output the sharers vectors registers
          sharers_v_o = 1'b1;

          // and give the register file a cycle to capture the outputs
          done_o = 1'b1;

          // go back to READY state
          dir_state_n = READY;

        end
        default: begin
          dir_state_n = RESET;
        end
      endcase
    end
  end

  // Reads are synchronous, with the address latched in the current cycle, and data available next
  // Writes take 1 cycle
  bsg_mem_1rw_sync_mask_write_bit
    #(.width_p(dir_row_width_lp)
      ,.els_p(dir_rows_lp)
      )
    directory
     (.clk_i(clk_i)
      ,.reset_i(reset_i)
      ,.w_i(dir_ram_w_v)
      ,.w_mask_i(dir_ram_w_mask)
      ,.addr_i(dir_ram_addr)
      ,.data_i(dir_ram_w_data)
      ,.v_i(dir_ram_v)
      ,.data_o(dir_row_lo)
      );

  // combinational logic to determine hit, way, and state for current directory row output
  bp_cce_dir_tag_checker
    #(.tag_sets_per_row_p(dir_tag_sets_per_row_lp)
      ,.rows_per_wg_p(dir_rows_per_wg_lp)
      ,.row_width_p(dir_row_width_lp)
      ,.lce_assoc_p(lce_assoc_p)
      ,.tag_width_p(tag_width_p)
     )
    tag_checker
     (.row_i(dir_row_lo)
      ,.row_v_i(dir_rd_v_r)
      ,.tag_i(tag_r)
      ,.sharers_hits_o(sharers_hits)
      ,.sharers_ways_o(sharers_ways)
      ,.sharers_coh_states_o(sharers_coh_states)
     );

  // TODO: currently unused, maybe for debug
  logic [`bp_cce_coh_bits-1:0] lru_coh_state_lo;

  bp_cce_dir_lru_extract
    #(.tag_sets_per_row_p(dir_tag_sets_per_row_lp)
      ,.rows_per_wg_p(dir_rows_per_wg_lp)
      ,.row_width_p(dir_row_width_lp)
      ,.lce_assoc_p(lce_assoc_p)
      ,.num_lce_p(num_lce_p)
      ,.tag_width_p(tag_width_p)
     )
    lru_extract
     (.row_i(dir_row_lo)
      ,.row_v_i(dir_rd_v_r)
      ,.wg_row_i(dir_rd_cnt_r)
      ,.lce_i(lce_r)
      ,.lru_way_i(lru_way_r)
      ,.lru_v_o(lru_v_o)
      ,.lru_coh_state_o(lru_coh_state_lo)
      ,.lru_cached_excl_o(lru_cached_excl_o)
      ,.lru_tag_o(lru_tag_o)
     );

  always_ff @(negedge clk_i) begin
    if (~reset_i) begin
      if (dir_ram_w_v & dir_ram_v) begin
        $display("%0T: writing directory addr[%H] wg[%0d] lce[%0d] way[%0d] ts[%0d] tag[%H] cs[%2b]\n%H\n%H"
                 , $time, dir_ram_addr, way_group_i, lce_i, way_i, tag_set_select, tag_i, coh_state_i
                 , dir_ram_w_mask, dir_ram_w_data);
      end
    end
  end

endmodule
