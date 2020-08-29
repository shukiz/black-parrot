/**
 *  bp_mcore_looper.v: A Multi-core HW looper to synchronize multi-core processing of loops.
 */
module bp_mcore_looper
    import bp_common_pkg::*;
    import bp_common_aviary_pkg::*;
    import bp_be_pkg::*;
    import bp_common_cfg_link_pkg::*;
    import bp_cce_pkg::*;
    import bsg_noc_pkg::*;
    import bsg_wormhole_router_pkg::*;
    import bp_me_pkg::*;
    #(parameter bp_params_e bp_params_p = e_bp_inv_cfg
    	`declare_bp_proc_params(bp_params_p)
    `declare_bp_me_if_widths(paddr_width_p, cce_block_width_p, lce_id_width_p, lce_assoc_p)
    
    // TODO: Should I be a global param?
    // num_core_p /* Shuki: Replaced 2 with num_core_p */
    , localparam mcore_looper_max_outstanding_p = 2
    	)
    	(input                                                clk_i
         , input                                              reset_i
        
         , input [cce_mem_msg_width_lp-1:0]                   mem_cmd_i
         , input                                              mem_cmd_v_i
         , output                                             mem_cmd_ready_o
        
         , output [cce_mem_msg_width_lp-1:0]                  mem_resp_o
         , output                                             mem_resp_v_o
         , input                                              mem_resp_yumi_i
        
         // Local interrupts
         , output                                             software_irq_o
         , output                                             timer_irq_o
         , output                                             external_irq_o
         
         // debug
         , output                                             hwlooper_control_w_v_li_debug
         , output [dword_width_p-1:0]                         hwlooper_control_n_debug
         , output [dword_width_p-1:0]                         control_r_debug
         , output [cce_mem_msg_width_lp-1:0]                  fifo_out_mem_cmd_lo_debug
        );
    
    `declare_bp_me_if(paddr_width_p, cce_block_width_p, lce_id_width_p, lce_assoc_p);
    
    bp_cce_mem_msg_s mem_cmd_li, mem_cmd_lo;
    assign mem_cmd_li = mem_cmd_i;
    
    logic small_fifo_v_lo, small_fifo_yumi_li;
    bsg_fifo_1r1w_small
        #(.width_p($bits(bp_cce_mem_msg_s)), .els_p(mcore_looper_max_outstanding_p))
        small_fifo
        (.clk_i(clk_i)
         ,.reset_i(reset_i)
        
         ,.data_i(mem_cmd_li)
         ,.v_i(mem_cmd_v_i)
         ,.ready_o(mem_cmd_ready_o)
        
         ,.data_o(mem_cmd_lo)
         ,.v_o(small_fifo_v_lo)
         ,.yumi_i(small_fifo_yumi_li)
        );

    /* Different signals into the multicore-looper */
    
    logic control_cmd_v;
    logic global_start_index_cmd_v;
    logic global_end_index_cmd_v;
    logic next_alloc_start_index_cmd_v;
    logic allocation_size_cmd_v;
    logic wr_not_rd;

	bp_local_addr_s local_addr;
	assign local_addr = mem_cmd_lo.header.addr;

	always_comb
	begin
        control_cmd_v                = 1'b0;
        global_start_index_cmd_v     = 1'b0;
        global_end_index_cmd_v       = 1'b0;
        next_alloc_start_index_cmd_v = 1'b0;
        allocation_size_cmd_v        = 1'b0;

		wr_not_rd = mem_cmd_lo.header.msg_type inside {e_cce_mem_wr, e_cce_mem_uc_wr};

		unique 
		casez ({local_addr.dev, local_addr.addr})
            hw_looper_control_reg_addr_gp                : control_cmd_v                = small_fifo_v_lo;
            hw_looper_global_start_index_reg_addr_gp     : global_start_index_cmd_v     = small_fifo_v_lo;
            hw_looper_global_end_index_reg_addr_gp       : global_end_index_cmd_v       = small_fifo_v_lo;
            hw_looper_next_alloc_start_index_reg_addr_gp : next_alloc_start_index_cmd_v = small_fifo_v_lo;
            hw_looper_allocation_size_reg_addr_gp        : allocation_size_cmd_v        = small_fifo_v_lo;
			default: begin end
		endcase
	end	
    
    logic [dword_width_p-1:0] control_r;
    logic [dword_width_p-1:0] global_start_index_r;
    logic [dword_width_p-1:0] global_end_index_r;
    logic [dword_width_p-1:0] next_alloc_start_index_r;
    logic [dword_width_p-1:0] allocation_size_r;

    logic [dword_width_p-1:0] hwlooper_control_n;
    logic [dword_width_p-1:0] hwlooper_global_start_index_n;
    logic [dword_width_p-1:0] hwlooper_global_end_index_n;
    logic [dword_width_p-1:0] hwlooper_next_alloc_start_index_n;
    logic [dword_width_p-1:0] hwlooper_allocation_size_n;
    
    /* 
       A 64-bit register in the following format:
       [Allocation last_index<HIGH 32bit> : Allocation start_index<LOW 32bit>]
    */
    logic [dword_width_p-1:0] hwlooper_work_allocation_n;
    
    /* hw_looper_control_reg Instantiation */
    assign hwlooper_control_n = mem_cmd_lo.data[0+:dword_width_p];
    wire hwlooper_control_w_v_li = wr_not_rd & control_cmd_v;
    bsg_dff_reset_en
        #(.width_p(dword_width_p))
        hw_looper_control_reg
        (.clk_i(clk_i)
         ,.reset_i(reset_i)
            
         ,.en_i(hwlooper_control_w_v_li)
         ,.data_i(hwlooper_control_n)
         ,.data_o(control_r)
        );
    //assign external_irq_o = control_r;

    /* hw_looper_global_start_index_reg Instantiation */
    assign hwlooper_global_start_index_n = mem_cmd_lo.data[0+:dword_width_p];
    wire hwlooper_global_start_index_w_v_li = wr_not_rd & global_start_index_cmd_v;
    bsg_dff_reset_en
        #(.width_p(dword_width_p))
        hw_looper_global_start_index_reg
        (.clk_i(clk_i)
         ,.reset_i(reset_i)
            
         ,.en_i(hwlooper_global_start_index_w_v_li)
         ,.data_i(hwlooper_global_start_index_n)
         ,.data_o(global_start_index_r)
        );
    //assign external_irq_o = global_start_index_r;

    /* hw_looper_global_end_index_reg Instantiation */
    assign hwlooper_global_end_index_n = mem_cmd_lo.data[0+:dword_width_p];
    wire hwlooper_global_end_index_w_v_li = wr_not_rd & global_end_index_cmd_v;
    bsg_dff_reset_en
        #(.width_p(dword_width_p))
        hw_looper_global_end_index_reg
        (.clk_i(clk_i)
         ,.reset_i(reset_i)

         ,.en_i(hwlooper_global_end_index_w_v_li)
         ,.data_i(hwlooper_global_end_index_n)
         ,.data_o(global_end_index_r)
        );
    //assign external_irq_o = global_end_index_r;

    /* hw_looper_next_alloc_start_index_reg Instantiation */
    //assign hwlooper_next_alloc_start_index_n = mem_cmd_lo.data[0+:dword_width_p];
        
    //assign hwlooper_next_alloc_start_index_n =
    //    min( (next_alloc_start_index_r + allocation_size_r), global_end_index_r) );
    always @* begin
        if ( (next_alloc_start_index_r + allocation_size_r) > global_end_index_r)
            hwlooper_next_alloc_start_index_n = global_end_index_r;
        else
            hwlooper_next_alloc_start_index_n = (next_alloc_start_index_r + allocation_size_r);
    end
    
    assign hwlooper_work_allocation_n = 
        (hwlooper_next_alloc_start_index_n << 32) | next_alloc_start_index_r;
            
    wire hwlooper_next_alloc_start_index_w_v_li = /*wr_not_rd &*/ next_alloc_start_index_cmd_v;
    bsg_dff_reset_en
        #(.width_p(dword_width_p))
        hw_looper_next_alloc_start_index_reg
        (.clk_i(clk_i)
         ,.reset_i(reset_i)

         ,.en_i(hwlooper_next_alloc_start_index_w_v_li)
         ,.data_i(hwlooper_next_alloc_start_index_n)
         ,.data_o(next_alloc_start_index_r)
        );
    //assign external_irq_o = next_alloc_start_index_r;

    /* hw_looper_allocation_size_reg Instantiation */
    assign hwlooper_allocation_size_n = mem_cmd_lo.data[0+:dword_width_p];
    wire hwlooper_allocation_size_w_v_li = wr_not_rd & allocation_size_cmd_v;
    bsg_dff_reset_en
        #(.width_p(dword_width_p))
        hw_looper_allocation_size_reg
        (.clk_i(clk_i)
         ,.reset_i(reset_i)

         ,.en_i(hwlooper_allocation_size_w_v_li)
         ,.data_i(hwlooper_allocation_size_n)
         ,.data_o(allocation_size_r)
        );
    //assign external_irq_o = allocation_size_r;
            
    /* Select register read */
    wire [dword_width_p-1:0] rdata_lo = control_cmd_v 
        ? dword_width_p'(control_r)
        : global_start_index_cmd_v 
          ? dword_width_p'(global_start_index_r)
          : global_end_index_cmd_v 
            ? dword_width_p'(global_end_index_r)
            : next_alloc_start_index_cmd_v 
              ? dword_width_p'(hwlooper_work_allocation_n /*next_alloc_start_index_r*/)
              : dword_width_p'(allocation_size_r); /* else ==> allocation_size_cmd_v */
        
    
    bp_cce_mem_msg_s mem_resp_lo;
    assign mem_resp_lo =
        '{header : '{
                msg_type       : mem_cmd_lo.header.msg_type
                ,addr          : mem_cmd_lo.header.addr
                ,payload       : mem_cmd_lo.header.payload
                ,size          : mem_cmd_lo.header.size
            }
            ,data          : cce_block_width_p'(rdata_lo)
        };
    assign mem_resp_o = mem_resp_lo;
    assign mem_resp_v_o = small_fifo_v_lo;
    assign small_fifo_yumi_li = mem_resp_yumi_i;
    
    assign hwlooper_control_w_v_li_debug = hwlooper_control_w_v_li;
    assign hwlooper_control_n_debug = hwlooper_control_n;
    assign fifo_out_mem_cmd_lo_debug = mem_cmd_lo;
    assign control_r_debug = control_r;

endmodule
