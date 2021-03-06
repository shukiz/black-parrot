/**
 *  Name:
 *    bp_lce_req.v
 *
 *  Description:
 *    LCE request handler.
 *
 *    When a cache miss is present to the LCE, the LCE request handler issues a new
 *    LCE request to the coherenece system to request the desired cache block, or to
 *    perform an uncached access.
 *
 */

module bp_lce_req
  import bp_common_pkg::*;
  import bp_common_aviary_pkg::*;
 #(parameter bp_params_e bp_params_p = e_bp_inv_cfg
   `declare_bp_proc_params(bp_params_p)

    // parameters specific to this LCE
    , parameter assoc_p = "inv"
    , parameter sets_p = "inv"
    , parameter block_width_p = "inv"
    , parameter fill_width_p = block_width_p


    // maximum number of outstanding transactions
    , parameter credits_p = coh_noc_max_credits_p

    // issue non-exclusive read requests
    , parameter non_excl_reads_p = 0

    , localparam block_size_in_bytes_lp = (block_width_p/8)
    , localparam lg_sets_lp = `BSG_SAFE_CLOG2(sets_p)
    , localparam lg_block_size_in_bytes_lp = `BSG_SAFE_CLOG2(block_size_in_bytes_lp)
    , localparam ptag_width_lp = (paddr_width_p-lg_sets_lp-lg_block_size_in_bytes_lp)
    , localparam lg_lce_assoc_lp = `BSG_SAFE_CLOG2(lce_assoc_p)

   `declare_bp_lce_cce_if_header_widths(cce_id_width_p, lce_id_width_p, paddr_width_p, lce_assoc_p)
   `declare_bp_lce_cce_if_widths(cce_id_width_p, lce_id_width_p, paddr_width_p, lce_assoc_p, cce_block_width_p)
   `declare_bp_cache_service_if_widths(paddr_width_p, ptag_width_lp, sets_p, assoc_p, dword_width_p, block_width_p, fill_width_p, cache)

    , localparam stat_info_width_lp = `bp_cache_stat_info_width(assoc_p)

    // coherence request size for cached requests
    // block size smaller than 8-bytes not supported
    , localparam bp_mem_msg_size_e req_block_size_lp =
      (block_size_in_bytes_lp == 128)
      ? e_mem_msg_size_128
      : (block_size_in_bytes_lp == 64)
        ? e_mem_msg_size_64
        : (block_size_in_bytes_lp == 32)
          ? e_mem_msg_size_32
          : (block_size_in_bytes_lp == 16)
            ? e_mem_msg_size_16
            : e_mem_msg_size_8
  )
  (
    input                                            clk_i
    , input                                          reset_i

    // LCE Configuration
    , input [lce_id_width_p-1:0]                     lce_id_i
    , input bp_lce_mode_e                            lce_mode_i

    // Cache-LCE Interface
    // ready_o->valid_i handshake
    // metadata arrives in the same cycle as req, or any cycle after, but before the next request
    // can arrive, as indicated by the metadata_v_i signal
    , input [cache_req_width_lp-1:0]                 cache_req_i
    , input                                          cache_req_v_i
    , output logic                                   cache_req_ready_o
    , input [cache_req_metadata_width_lp-1:0]        cache_req_metadata_i
    , input                                          cache_req_metadata_v_i

    // LCE-Cache Interface
    , output logic                                   credits_full_o
    , output logic                                   credits_empty_o

    // LCE Cmd - LCE Req Interface
    // request complete signal from LCE Cmd module - Cached Load/Store and Uncached Load
    // this signal is raised exactly once, for a single cycle, per request completing, and it
    // can be raised at any time after the LCE request sends out
    , input                                          cache_req_complete_i

    // Uncached Store request complete signal
    , input                                          uc_store_req_complete_i

    // LCE Request out
    // ready->valid
    , output logic [lce_cce_req_width_lp-1:0]        lce_req_o
    , output logic                                   lce_req_v_o
    , input                                          lce_req_ready_i
  );

  `declare_bp_lce_cce_if(cce_id_width_p, lce_id_width_p, paddr_width_p, lce_assoc_p, cce_block_width_p);
  `declare_bp_cache_service_if(paddr_width_p, ptag_width_lp, sets_p, assoc_p, dword_width_p, block_width_p, fill_width_p, cache);

  // FSM states
  typedef enum logic [2:0] {
    e_reset
    ,e_ready
    ,e_send_cached_req
    ,e_send_uncached_req
  } lce_req_state_e;
  lce_req_state_e state_n, state_r;

  bp_lce_cce_req_s lce_req;
  assign lce_req_o = lce_req;

  bp_cache_req_s cache_req_r;
  bsg_dff_en_bypass
    #(.width_p($bits(bp_cache_req_s)))
    req_reg
     (.clk_i(clk_i)
      ,.en_i(cache_req_v_i)
      ,.data_i(cache_req_i)
      ,.data_o(cache_req_r)
      );

  bp_cache_req_metadata_s cache_req_metadata_r;
  bsg_dff_en_bypass
   #(.width_p($bits(bp_cache_req_metadata_s)))
   metadata_reg
    (.clk_i(clk_i)
     ,.en_i(cache_req_metadata_v_i)
     ,.data_i(cache_req_metadata_i)
     ,.data_o(cache_req_metadata_r)
     );

  logic cache_req_metadata_v_r;
  logic cache_req_metadata_v_en;
  logic cache_req_metadata_v_li;
  bsg_dff_en
   #(.width_p(1))
   metadata_v_reg
    (.clk_i(clk_i)
     ,.en_i(cache_req_metadata_v_en)
     ,.data_i(cache_req_metadata_v_li)
     ,.data_o(cache_req_metadata_v_r)
     );

  // Outstanding request credit counter
  logic [`BSG_WIDTH(credits_p)-1:0] credit_count_lo;
  wire credit_v_li = lce_req_v_o;
  wire credit_ready_li = lce_req_ready_i;
  wire credit_returned_li = cache_req_complete_i | uc_store_req_complete_i;
  bsg_flow_counter
    #(.els_p(credits_p))
    req_counter
      (.clk_i(clk_i)
      ,.reset_i(reset_i)
      ,.v_i(credit_v_li)
      ,.ready_i(credit_ready_li)
      ,.yumi_i(credit_returned_li)
      ,.count_o(credit_count_lo)
      );
  assign credits_full_o = (credit_count_lo == credits_p);
  assign credits_empty_o = (credit_count_lo == '0);

  // Request Address to CCE
  logic [cce_id_width_p-1:0] req_cce_id_lo;
  bp_me_addr_to_cce_id
   #(.bp_params_p(bp_params_p))
   req_map
    (.paddr_i(lce_req.header.addr)
     ,.cce_id_o(req_cce_id_lo)
     );

  always_comb begin
    state_n = state_r;

    cache_req_ready_o = 1'b0;

    cache_req_metadata_v_en = 1'b0;
    cache_req_metadata_v_li = 1'b0;

    lce_req_v_o = 1'b0;

    // Request message defaults
    lce_req = '0;
    lce_req.header.dst_id = req_cce_id_lo;
    lce_req.header.src_id = lce_id_i;
    lce_req.header.addr = cache_req_r.addr;
    lce_req.header.msg_type = e_lce_req_type_rd;

    unique case (state_r)

      e_reset: begin
        state_n = e_ready;
        // reset the metadata valid register
        cache_req_metadata_v_en = 1'b1;
      end

      // Ready for new request
      e_ready: begin
        // ready for new request if LCE hasn't used all its credits
        cache_req_ready_o = ~credits_full_o;
        if (cache_req_v_i) begin
          unique case (cache_req_r.msg_type)
            e_miss_store
            , e_miss_load: begin
              state_n = e_send_cached_req;
            end
            e_uc_store
            , e_uc_load: begin
              state_n = e_send_uncached_req;
            end
            default: begin
            end
          endcase
        end
      end

      // Cached Request
      e_send_cached_req: begin
        // valid cache request arrived last cycle (or earlier) and is held in cache_req_r

        // send when port is ready and metadata has arrived
        lce_req_v_o = lce_req_ready_i & (cache_req_metadata_v_i | cache_req_metadata_v_r);

        lce_req.header.lru_way_id = lg_lce_assoc_lp'(cache_req_metadata_r.repl_way);
        lce_req.header.size = req_block_size_lp;
        lce_req.header.msg_type = (cache_req_r.msg_type == e_miss_load)
          ? e_lce_req_type_rd
          : e_lce_req_type_wr;

        lce_req.header.non_exclusive = (cache_req_r.msg_type == e_miss_load)
          ? (non_excl_reads_p == 1)
            ? e_lce_req_non_excl
            : e_lce_req_excl
          : e_lce_req_excl;

        state_n = lce_req_v_o
          ? e_ready
          : e_send_cached_req;

        // cache_metadata arrives this cycle (or following cycle) into bypass DFF
        // register is set when lce request isn't able to send, and cleared when request sends
        cache_req_metadata_v_en = cache_req_metadata_v_i | lce_req_v_o;
        cache_req_metadata_v_li = ~lce_req_v_o;

      end

      // Uncached Request
      e_send_uncached_req: begin
        // valid cache request arrived last cycle (or earlier) and is held in cache_req_r

        // send when port is ready and metadata has arrived
        lce_req_v_o = lce_req_ready_i & (cache_req_metadata_v_i | cache_req_metadata_v_r);

        lce_req.data[0+:dword_width_p] = (cache_req_r.msg_type == e_uc_load)
          ? '0
          : cache_req_r.data[0+:dword_width_p];
        lce_req.header.size = bp_mem_msg_size_e'(cache_req_r.size);
        lce_req.header.msg_type = (cache_req_r.msg_type == e_uc_load)
          ? e_lce_req_type_uc_rd
          : e_lce_req_type_uc_wr;

        state_n = lce_req_v_o
          ? e_ready
          : e_send_uncached_req;

        // cache_metadata arrives this cycle (or following cycle) into bypass DFF
        // register is set when lce request isn't able to send, and cleared when request sends
        cache_req_metadata_v_en = cache_req_metadata_v_i | lce_req_v_o;
        cache_req_metadata_v_li = ~lce_req_v_o;

      end

      default: begin
        state_n = e_reset;
      end
    endcase
  end

  // synopsys sync_set_reset "reset_i"
  always_ff @ (posedge clk_i) begin
    if (reset_i) begin
      state_r <= e_reset;
    end
    else begin
      state_r <= state_n;
    end
  end

endmodule
