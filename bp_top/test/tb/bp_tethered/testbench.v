/**
  *
  * testbench.v
  *
  */

`include "bsg_noc_links.vh"

module testbench
 import bp_common_pkg::*;
 import bp_common_aviary_pkg::*;
 import bp_be_pkg::*;
 import bp_common_rv64_pkg::*;
 import bp_cce_pkg::*;
 import bp_me_pkg::*;
 import bp_common_cfg_link_pkg::*;
 import bsg_noc_pkg::*;
 #(parameter bp_params_e bp_params_p = BP_CFG_FLOWVAR // Replaced by the flow with a specific bp_cfg
   `declare_bp_proc_params(bp_params_p)
   `declare_bp_fe_be_if_widths(vaddr_width_p, paddr_width_p, asid_width_p, branch_metadata_fwd_width_p)
   `declare_bp_me_if_widths(paddr_width_p, cce_block_width_p, lce_id_width_p, lce_assoc_p)

   // Tracing parameters
   , parameter calc_trace_p                = 0
   , parameter cce_trace_p                 = 0
   , parameter lce_trace_p                 = 0
   , parameter cmt_trace_p                 = 0
   , parameter dram_trace_p                = 0
   , parameter npc_trace_p                 = 0
   , parameter icache_trace_p              = 0
   , parameter dcache_trace_p              = 0
   , parameter vm_trace_p                  = 0
   , parameter core_profile_p              = 0
   , parameter preload_mem_p               = 0
   , parameter checkpoint_p                = 0
   , parameter cosim_p                     = 0
   , parameter cosim_memsize_p             = 256
   , parameter cosim_cfg_file_p            = "prog.cfg"
   , parameter cosim_instr_p               = 0
   , parameter warmup_instr_p              = 0

   , parameter mem_zero_p         = 1
   , parameter mem_file_p         = "prog.mem"
   , parameter mem_cap_in_bytes_p = 2**28
   , parameter [paddr_width_p-1:0] mem_offset_p = dram_base_addr_gp

   // Number of elements in the fake BlackParrot memory
   , parameter use_max_latency_p      = 0
   , parameter use_random_latency_p   = 0
   , parameter use_dramsim2_latency_p = 0

   , parameter max_latency_p = 15

   , parameter dram_clock_period_in_ps_p = `BP_SIM_CLK_PERIOD
   , parameter dram_cfg_p                = "dram_ch.ini"
   , parameter dram_sys_cfg_p            = "dram_sys.ini"
   , parameter dram_capacity_p           = 16384
   )
  (input clk_i
   , input reset_i
   );

`declare_bp_me_if(paddr_width_p, cce_block_width_p, lce_id_width_p, lce_assoc_p)

logic [num_core_p-1:0] program_finish_lo;
logic [num_core_p-1:0] cosim_finish_lo;

bp_cce_mem_msg_s proc_mem_cmd_lo;
logic proc_mem_cmd_v_lo, proc_mem_cmd_ready_li;
bp_cce_mem_msg_s proc_mem_resp_li;
logic proc_mem_resp_v_li, proc_mem_resp_yumi_lo;

bp_cce_mem_msg_s proc_io_cmd_lo;
logic proc_io_cmd_v_lo, proc_io_cmd_ready_li;
bp_cce_mem_msg_s proc_io_resp_li;
logic proc_io_resp_v_li, proc_io_resp_yumi_lo;

bp_cce_mem_msg_s io_cmd_lo;
logic io_cmd_v_lo, io_cmd_ready_li;
bp_cce_mem_msg_s io_resp_li;
logic io_resp_v_li, io_resp_yumi_lo;

bp_cce_mem_msg_s load_cmd_lo;
logic load_cmd_v_lo, load_cmd_yumi_li;
bp_cce_mem_msg_s load_resp_li;
logic load_resp_v_li, load_resp_ready_lo;

wrapper
 #(.bp_params_p(bp_params_p))
 wrapper
  (.clk_i(clk_i)
   ,.reset_i(reset_i)

   ,.io_cmd_o(proc_io_cmd_lo)
   ,.io_cmd_v_o(proc_io_cmd_v_lo)
   ,.io_cmd_ready_i(proc_io_cmd_ready_li)

   ,.io_resp_i(proc_io_resp_li)
   ,.io_resp_v_i(proc_io_resp_v_li)
   ,.io_resp_yumi_o(proc_io_resp_yumi_lo)

   ,.io_cmd_i(load_cmd_lo)
   ,.io_cmd_v_i(load_cmd_v_lo)
   ,.io_cmd_yumi_o(load_cmd_yumi_li)

   ,.io_resp_o(load_resp_li)
   ,.io_resp_v_o(load_resp_v_li)
   ,.io_resp_ready_i(load_resp_ready_lo)

   ,.mem_cmd_o(proc_mem_cmd_lo)
   ,.mem_cmd_v_o(proc_mem_cmd_v_lo)
   ,.mem_cmd_ready_i(proc_mem_cmd_ready_li)

   ,.mem_resp_i(proc_mem_resp_li)
   ,.mem_resp_v_i(proc_mem_resp_v_li)
   ,.mem_resp_yumi_o(proc_mem_resp_yumi_lo)
   );

bp_mem
 #(.bp_params_p(bp_params_p)
   ,.mem_cap_in_bytes_p(mem_cap_in_bytes_p)
   ,.mem_load_p(preload_mem_p)
   ,.mem_zero_p(mem_zero_p)
   ,.mem_file_p(mem_file_p)
   ,.mem_offset_p(mem_offset_p)

   ,.use_max_latency_p(use_max_latency_p)
   ,.use_random_latency_p(use_random_latency_p)
   ,.use_dramsim2_latency_p(use_dramsim2_latency_p)
   ,.max_latency_p(max_latency_p)

   ,.dram_clock_period_in_ps_p(dram_clock_period_in_ps_p)
   ,.dram_cfg_p(dram_cfg_p)
   ,.dram_sys_cfg_p(dram_sys_cfg_p)
   ,.dram_capacity_p(dram_capacity_p)
   )
 mem
  (.clk_i(clk_i)
   ,.reset_i(reset_i)

   ,.mem_cmd_i(proc_mem_cmd_lo)
   ,.mem_cmd_v_i(proc_mem_cmd_ready_li & proc_mem_cmd_v_lo)
   ,.mem_cmd_ready_o(proc_mem_cmd_ready_li)

   ,.mem_resp_o(proc_mem_resp_li)
   ,.mem_resp_v_o(proc_mem_resp_v_li)
   ,.mem_resp_yumi_i(proc_mem_resp_yumi_lo)
   );

bp_nonsynth_nbf_loader
 #(.bp_params_p(bp_params_p))
 nbf_loader
  (.clk_i(clk_i)
   ,.reset_i(reset_i)

   ,.lce_id_i(lce_id_width_p'('b10))
    
   ,.io_cmd_o(load_cmd_lo)
   ,.io_cmd_v_o(load_cmd_v_lo)
   ,.io_cmd_yumi_i(load_cmd_yumi_li)

   ,.io_resp_i(load_resp_li)
   ,.io_resp_v_i(load_resp_v_li)
   ,.io_resp_ready_o(load_resp_ready_lo)
   );

bp_nonsynth_host
 #(.bp_params_p(bp_params_p))
 host
  (.clk_i(clk_i)
   ,.reset_i(reset_i)

   ,.io_cmd_i(proc_io_cmd_lo)
   ,.io_cmd_v_i(proc_io_cmd_v_lo & proc_io_cmd_ready_li)
   ,.io_cmd_ready_o(proc_io_cmd_ready_li)

   ,.io_resp_o(proc_io_resp_li)
   ,.io_resp_v_o(proc_io_resp_v_li)
   ,.io_resp_yumi_i(proc_io_resp_yumi_lo)

   ,.program_finish_o(program_finish_lo)
   );

bind bp_be_top
  bp_nonsynth_commit_tracer
   #(.bp_params_p(bp_params_p))
   commit_tracer
    (.clk_i(clk_i & (testbench.cmt_trace_p == 1))
     ,.reset_i(reset_i)
     ,.freeze_i(be_checker.scheduler.int_regfile.cfg_bus.freeze)

     ,.mhartid_i(be_checker.scheduler.int_regfile.cfg_bus.core_id)

     ,.decode_i(be_calculator.reservation_n.decode)

     ,.commit_v_i(be_calculator.commit_pkt.instret)
     ,.commit_pc_i(be_calculator.commit_pkt.pc)
     ,.commit_instr_i(be_calculator.commit_pkt.instr)

     ,.rd_w_v_i(be_checker.scheduler.wb_pkt.rd_w_v)
     ,.rd_addr_i(be_checker.scheduler.wb_pkt.rd_addr)
     ,.rd_data_i(be_checker.scheduler.wb_pkt.rd_data)
     );

bind bp_be_top
  bp_nonsynth_cosim
   #(.bp_params_p(bp_params_p))
   cosim
    (.clk_i(clk_i)
     ,.reset_i(reset_i)
     ,.freeze_i(be_checker.scheduler.int_regfile.cfg_bus.freeze)

     // We want to pass these values as parameters, but cannot in Verilator 4.025
     // Parameter-resolved constants must not use dotted references
     ,.en_i(testbench.cosim_p == 1)
     ,.checkpoint_i(testbench.checkpoint_p == 1)
     ,.num_core_i(testbench.num_core_p)
     ,.mhartid_i(be_checker.scheduler.int_regfile.cfg_bus.core_id)
     ,.config_file_i(testbench.cosim_cfg_file_p)
     ,.instr_cap_i(testbench.cosim_instr_p)
     ,.memsize_i(testbench.cosim_memsize_p)

     ,.decode_i(be_calculator.reservation_n.decode)

     ,.commit_v_i(be_calculator.commit_pkt.instret)
     ,.commit_pc_i(be_calculator.commit_pkt.pc)
     ,.commit_instr_i(be_calculator.commit_pkt.instr)

     ,.rd_w_v_i(be_checker.scheduler.wb_pkt.rd_w_v)
     ,.rd_addr_i(be_checker.scheduler.wb_pkt.rd_addr)
     ,.rd_data_i(be_checker.scheduler.wb_pkt.rd_data)

     ,.interrupt_v_i(be_mem.csr.trap_pkt_cast_o._interrupt)
     ,.cause_i(be_mem.csr.trap_pkt_cast_o.cause)
     // TODO: Find a way to access the finish_o signals for each core
     ,.finish_o()
     );

assign cosim_finish_lo = '0;

bind bp_be_top
  bp_be_nonsynth_perf
   #(.bp_params_p(bp_params_p))
   perf
    (.clk_i(clk_i)
     ,.reset_i(reset_i)
     ,.freeze_i(be_checker.scheduler.int_regfile.cfg_bus.freeze)
     ,.warmup_instr_i(testbench.warmup_instr_p)

     ,.mhartid_i(be_checker.scheduler.int_regfile.cfg_bus.core_id)

     ,.commit_v_i(be_calculator.commit_pkt.instret)

     ,.program_finish_i(testbench.program_finish_lo | testbench.cosim_finish_lo)
     );

  bind bp_be_top
    bp_nonsynth_watchdog
     #(.bp_params_p(bp_params_p)
       ,.timeout_cycles_p(100000)
       ,.heartbeat_instr_p(100000)
       )
     watchdog
      (.clk_i(clk_i)
       ,.reset_i(reset_i)
       ,.freeze_i(be_checker.scheduler.int_regfile.cfg_bus.freeze)

       ,.mhartid_i(be_checker.scheduler.int_regfile.cfg_bus.core_id)

       ,.npc_i(be_checker.director.npc_r)
       ,.instret_i(be_calculator.commit_pkt.instret)
       );

  bind bp_be_director
    bp_be_nonsynth_npc_tracer
     #(.bp_params_p(bp_params_p))
     npc_tracer
      (.clk_i(clk_i & (testbench.npc_trace_p == 1))
       ,.reset_i(reset_i)
       ,.freeze_i(be_checker.scheduler.int_regfile.cfg_bus.freeze)

       ,.mhartid_i(be_checker.scheduler.int_regfile.cfg_bus.core_id)

       ,.npc_w_v(npc_w_v)
       ,.npc_n(npc_n)
       ,.npc_r(npc_r)
       ,.expected_npc_o(expected_npc_o)

       ,.fe_cmd_i(fe_cmd)
       ,.fe_cmd_v(fe_cmd_v)

       ,.commit_pkt_i(commit_pkt)
       );

  bind bp_be_dcache
    bp_nonsynth_cache_tracer
     #(.bp_params_p(bp_params_p)
      ,.assoc_p(dcache_assoc_p)
      ,.sets_p(dcache_sets_p)
      ,.block_width_p(dcache_block_width_p)
      ,.fill_width_p(dcache_fill_width_p)
      ,.trace_file_p("dcache"))
     dcache_tracer
      (.clk_i(clk_i & (testbench.dcache_trace_p == 1))
       ,.reset_i(reset_i)
       ,.freeze_i(cfg_bus_cast_i.freeze)

       ,.mhartid_i(cfg_bus_cast_i.core_id)

       ,.v_tl_r(v_tl_r)

       ,.v_tv_r(v_tv_r)
       ,.addr_tv_r(paddr_tv_r)
       ,.lr_miss_tv(lr_miss_tv)
       ,.sc_op_tv_r(sc_op_tv_r)
       ,.sc_success(sc_success)

       ,.cache_req_v_o(cache_req_v_o)
       ,.cache_req_o(cache_req_o)

       ,.cache_req_metadata_o(cache_req_metadata_o)
       ,.cache_req_metadata_v_o(cache_req_metadata_v_o)

       ,.cache_req_complete_i(cache_req_complete_i)

       ,.v_o(v_o)
       ,.load_data(data_o)
       ,.cache_miss_o(dcache_miss_o)
       ,.wt_req(wt_req)
       ,.store_data(data_tv_r)

       ,.data_mem_pkt_v_i(data_mem_pkt_v_i)
       ,.data_mem_pkt_i(data_mem_pkt_i)
       ,.data_mem_pkt_yumi_o(data_mem_pkt_yumi_o)

       ,.tag_mem_pkt_v_i(tag_mem_pkt_v_i)
       ,.tag_mem_pkt_i(tag_mem_pkt_i)
       ,.tag_mem_pkt_yumi_o(tag_mem_pkt_yumi_o)

       ,.stat_mem_pkt_v_i(stat_mem_pkt_v_i)
       ,.stat_mem_pkt_i(stat_mem_pkt_i)
       ,.stat_mem_pkt_yumi_o(stat_mem_pkt_yumi_o)

       ,.tag_mem_v_i(tag_mem_v_li)
       ,.data_mem_v_i(data_mem_v_li)
       ,.program_finish_i(testbench.program_finish_lo)
       );

  bind bp_fe_icache
    bp_nonsynth_cache_tracer
     #(.bp_params_p(bp_params_p)
      ,.assoc_p(icache_assoc_p)
      ,.sets_p(icache_sets_p)
      ,.block_width_p(icache_block_width_p)
      ,.fill_width_p(icache_fill_width_p)
      ,.trace_file_p("icache"))
     icache_tracer
      (.clk_i(clk_i & (testbench.icache_trace_p == 1))
       ,.reset_i(reset_i)

       ,.freeze_i(cfg_bus_cast_i.freeze)
       ,.mhartid_i(cfg_bus_cast_i.core_id)

       ,.v_tl_r(v_tl_r)

       ,.v_tv_r(v_tv_r)
       ,.addr_tv_r(addr_tv_r)
       ,.lr_miss_tv(1'b0)
       ,.sc_op_tv_r(1'b0)
       ,.sc_success(1'b0)

       ,.cache_req_v_o(cache_req_v_o)
       ,.cache_req_o(cache_req_o)

       ,.cache_req_metadata_o(cache_req_metadata_o)
       ,.cache_req_metadata_v_o(cache_req_metadata_v_o)

       ,.cache_req_complete_i(cache_req_complete_i)

       ,.v_o(data_v_o)
       ,.load_data(dword_width_p'(data_o))
       ,.cache_miss_o(miss_o)
       ,.wt_req()
       ,.store_data(dword_width_p'(0))

       ,.data_mem_pkt_v_i(data_mem_pkt_v_i)
       ,.data_mem_pkt_i(data_mem_pkt_i)
       ,.data_mem_pkt_yumi_o(data_mem_pkt_yumi_o)

       ,.tag_mem_pkt_v_i(tag_mem_pkt_v_i)
       ,.tag_mem_pkt_i(tag_mem_pkt_i)
       ,.tag_mem_pkt_yumi_o(tag_mem_pkt_yumi_o)

       ,.stat_mem_pkt_v_i(stat_mem_pkt_v_i)
       ,.stat_mem_pkt_i(stat_mem_pkt_i)
       ,.stat_mem_pkt_yumi_o(stat_mem_pkt_yumi_o)

       ,.tag_mem_v_i(tag_mem_v_li)
       ,.data_mem_v_i(data_mem_v_li)
       ,.program_finish_i(testbench.program_finish_lo)
       );

  bind bp_core_minimal
    bp_be_nonsynth_vm_tracer
    #(.bp_params_p(bp_params_p))
    vm_tracer
      (.clk_i(clk_i & (testbench.vm_trace_p == 1))
       ,.reset_i(reset_i)
       ,.freeze_i(be.be_checker.scheduler.int_regfile.cfg_bus.freeze)

       ,.mhartid_i(be.be_checker.scheduler.int_regfile.cfg_bus.core_id)

       ,.itlb_clear_i(fe.mem.itlb.flush_i)
       ,.itlb_fill_v_i(fe.mem.itlb.v_i & fe.mem.itlb.w_i)
       ,.itlb_vtag_i(fe.mem.itlb.vtag_i)
       ,.itlb_entry_i(fe.mem.itlb.entry_i)
       ,.itlb_cam_r_v_i(fe.mem.itlb.cam.r_v_i)

       ,.dtlb_clear_i(be.be_mem.dtlb.flush_i)
       ,.dtlb_fill_v_i(be.be_mem.dtlb.v_i & be.be_mem.dtlb.w_i)
       ,.dtlb_vtag_i(be.be_mem.dtlb.vtag_i)
       ,.dtlb_entry_i(be.be_mem.dtlb.entry_i)
       ,.dtlb_cam_r_v_i(be.be_mem.dtlb.cam.r_v_i)

       ,.program_finish_i(testbench.program_finish_lo)
       );

  bp_mem_nonsynth_tracer
   #(.bp_params_p(bp_params_p))
   bp_mem_tracer
    (.clk_i(clk_i & (testbench.dram_trace_p == 1))
     ,.reset_i(reset_i)

     ,.mem_cmd_i(proc_mem_cmd_lo)
     ,.mem_cmd_v_i(proc_mem_cmd_v_lo & proc_mem_cmd_ready_li)
     ,.mem_cmd_ready_i(proc_mem_cmd_ready_li)

     ,.mem_resp_i(proc_mem_resp_li)
     ,.mem_resp_v_i(proc_mem_resp_v_li)
     ,.mem_resp_yumi_i(proc_mem_resp_yumi_lo)
     );

  bind bp_core_minimal
    bp_nonsynth_core_profiler
     #(.bp_params_p(bp_params_p))
     core_profiler
      (.clk_i(clk_i & (testbench.core_profile_p == 1))
       ,.reset_i(reset_i)
       ,.freeze_i(be.be_checker.scheduler.int_regfile.cfg_bus.freeze)

       ,.mhartid_i(be.be_checker.scheduler.int_regfile.cfg_bus.core_id)

       ,.fe_wait_stall(fe.pc_gen.is_wait)
       ,.fe_queue_stall(~fe.pc_gen.fe_queue_ready_i)

       ,.itlb_miss(fe.mem.itlb_miss_r)
       ,.icache_miss(~fe.mem.icache.vaddr_ready_o | fe.pc_gen.icache_miss)
       ,.icache_fence(fe.mem.icache.fencei_req)
       ,.branch_override(fe.pc_gen.ovr_taken & ~fe.pc_gen.ovr_ret)
       ,.ret_override(fe.pc_gen.ovr_ret)

       ,.fe_cmd(fe.pc_gen.fe_cmd_yumi_o & ~fe.pc_gen.attaboy_v)

       ,.mispredict(be.be_checker.director.npc_mismatch_v)
       ,.target(be.be_checker.director.isd_status.isd_pc)

       ,.dtlb_miss(be.be_mem.dtlb_miss_r)
       ,.dcache_miss(~be.be_mem.dcache.ready_o)
       ,.long_haz(be.be_checker.detector.long_haz_v)
       ,.exception(be.be_checker.director.trap_pkt.exception)
       ,.eret(be.be_checker.director.trap_pkt.eret)
       ,._interrupt(be.be_checker.director.trap_pkt._interrupt)
       ,.control_haz(be.be_checker.detector.control_haz_v)
       ,.data_haz(be.be_checker.detector.data_haz_v)
       ,.load_dep((be.be_checker.detector.dep_status_li[0].mem_iwb_v
                   | be.be_checker.detector.dep_status_li[1].mem_iwb_v
                   ) & be.be_checker.detector.data_haz_v
                  )
       ,.mul_dep((be.be_checker.detector.dep_status_li[0].mul_iwb_v
                  | be.be_checker.detector.dep_status_li[1].mul_iwb_v
                  | be.be_checker.detector.dep_status_li[2].mul_iwb_v
                  ) & be.be_checker.detector.data_haz_v
                 )
       ,.struct_haz(be.be_checker.detector.struct_haz_v)

       ,.reservation(be.be_calculator.reservation_n)
       ,.commit_pkt(be.be_calculator.commit_pkt)
       ,.trap_pkt(be.be_mem.csr.trap_pkt_o)
       );

  bind bp_core_minimal
    bp_nonsynth_pc_profiler
     #(.bp_params_p(bp_params_p))
     pc_profiler
      (.clk_i(clk_i & (testbench.core_profile_p == 1))
       ,.reset_i(reset_i)
       ,.freeze_i(be.be_checker.scheduler.int_regfile.cfg_bus.freeze)

       ,.mhartid_i(be.be_checker.scheduler.int_regfile.cfg_bus.core_id)

       ,.commit_pkt(be.be_calculator.commit_pkt)

       ,.program_finish_i(testbench.program_finish_lo | testbench.cosim_finish_lo)
       );

  bind bp_be_director
    bp_nonsynth_branch_profiler
     #(.bp_params_p(bp_params_p))
     pc_profiler
      (.clk_i(clk_i & (testbench.core_profile_p == 1))
       ,.reset_i(reset_i)
       ,.freeze_i(cfg_bus_cast_i.freeze)

       ,.mhartid_i(cfg_bus_cast_i.core_id)

       ,.fe_cmd_o(fe_cmd_o)
       ,.fe_cmd_v_o(fe_cmd_v_o)
       ,.fe_cmd_ready_i(fe_cmd_ready_i)

       ,.commit_v_i(commit_pkt.instret)

       ,.program_finish_i(testbench.program_finish_lo | testbench.cosim_finish_lo)
       );

  if (cce_trace_p) begin : cce_tracer
  bind bp_cce_wrapper
    bp_me_nonsynth_cce_tracer
     #(.bp_params_p(bp_params_p))
     cce_tracer
      (.clk_i(clk_i & (testbench.cce_trace_p == 1))
      ,.reset_i(reset_i)
      ,.freeze_i(cfg_bus_cast_i.freeze)

      ,.cce_id_i(cfg_bus_cast_i.cce_id)

      // To CCE
      ,.lce_req_i(lce_req_i)
      ,.lce_req_v_i(lce_req_v_i)
      ,.lce_req_yumi_i(lce_req_yumi_o)
      ,.lce_resp_i(lce_resp_i)
      ,.lce_resp_v_i(lce_resp_v_i)
      ,.lce_resp_yumi_i(lce_resp_yumi_o)

      // From CCE
      ,.lce_cmd_i(lce_cmd_o)
      ,.lce_cmd_v_i(lce_cmd_v_o)
      ,.lce_cmd_ready_i(lce_cmd_ready_i)

      // To CCE
      ,.mem_resp_i(mem_resp_i)
      ,.mem_resp_v_i(mem_resp_v_i)
      ,.mem_resp_yumi_i(mem_resp_yumi_o)

      // From CCE
      ,.mem_cmd_i(mem_cmd_o)
      ,.mem_cmd_v_i(mem_cmd_v_o)
      ,.mem_cmd_ready_i(mem_cmd_ready_i)
      );
  end

  if (lce_trace_p) begin : lce_tracer
  bind bp_lce
    bp_me_nonsynth_lce_tracer
      #(.bp_params_p(bp_params_p)
        ,.sets_p(sets_p)
        ,.assoc_p(assoc_p)
        ,.block_width_p(block_width_p)
        )
      lce_tracer
      (.clk_i(clk_i & (testbench.lce_trace_p == 1))
      ,.reset_i(reset_i)
      ,.lce_id_i(lce_id_i)
      ,.lce_req_i(lce_req_o)
      ,.lce_req_v_i(lce_req_v_o)
      ,.lce_req_ready_i(lce_req_ready_i)
      ,.lce_resp_i(lce_resp_o)
      ,.lce_resp_v_i(lce_resp_v_o)
      ,.lce_resp_ready_i(lce_resp_ready_i)
      ,.lce_cmd_i(lce_cmd_i)
      ,.lce_cmd_v_i(lce_cmd_v_i)
      ,.lce_cmd_yumi_i(lce_cmd_yumi_o)
      ,.lce_cmd_o_i(lce_cmd_o)
      ,.lce_cmd_o_v_i(lce_cmd_v_o)
      ,.lce_cmd_o_ready_i(lce_cmd_ready_i)
      );
  end


bp_nonsynth_if_verif
 #(.bp_params_p(bp_params_p))
 if_verif
  ();

endmodule
