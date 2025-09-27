module calc_tb_top;

  import calc_tb_pkg::*;
  import calculator_pkg::*;

  parameter int DataSize = DATA_W;
  parameter int AddrSize = ADDR_W;
  logic clk = 0;
  logic rst;
  state_t state;
  logic [DataSize-1:0] rd_data;

  calc_if #(.DataSize(DataSize), .AddrSize(AddrSize)) calc_if(.clk(clk));
  top_lvl my_calc(
    .clk(clk),
    .rst(calc_if.reset),
    `ifdef VCS
    .read_start_addr(calc_if.read_start_addr),
    .read_end_addr(calc_if.read_end_addr),
    .write_start_addr(calc_if.write_start_addr),
    .write_end_addr(calc_if.write_end_addr)
    `endif
    `ifdef CADENCE
    .read_start_addr(calc_if.calc.read_start_addr),
    .read_end_addr(calc_if.calc.read_end_addr),
    .write_start_addr(calc_if.calc.write_start_addr),
    .write_end_addr(calc_if.calc.write_end_addr)
    `endif
  );

  assign rst = calc_if.reset;
  assign state = my_calc.u_ctrl.state;
  `ifdef VCS
  assign calc_if.wr_en = my_calc.write;
  assign calc_if.rd_en = my_calc.read;
  assign calc_if.wr_data = my_calc.w_data;
  assign calc_if.rd_data = my_calc.r_data;
  assign calc_if.ready = my_calc.u_ctrl.state == S_END;
  assign calc_if.curr_rd_addr = my_calc.r_addr;
  assign calc_if.curr_wr_addr = my_calc.w_addr;
  assign calc_if.loc_sel = my_calc.loc_sel;
  `endif
  `ifdef CADENCE
  assign calc_if.calc.wr_en = my_calc.write;
  assign calc_if.calc.rd_en = my_calc.read;
  assign calc_if.calc.wr_data = my_calc.w_data;
  assign calc_if.calc.rd_data = my_calc.r_data;
  assign calc_if.calc.ready = my_calc.u_ctrl.state == S_END;
  assign calc_if.calc.curr_rd_addr = my_calc.r_addr;
  assign calc_if.calc.curr_wr_addr = my_calc.w_addr;
  assign calc_if.calc.loc_sel = my_calc.loc_sel;
  `endif

  calc_tb_pkg::calc_driver #(.DataSize(DataSize), .AddrSize(AddrSize)) calc_driver_h;
  calc_tb_pkg::calc_sequencer #(.DataSize(DataSize), .AddrSize(AddrSize)) calc_sequencer_h;
  calc_tb_pkg::calc_monitor #(.DataSize(DataSize), .AddrSize(AddrSize)) calc_monitor_h;
  calc_tb_pkg::calc_sb #(.DataSize(DataSize), .AddrSize(AddrSize)) calc_sb_h;

  always #5 clk = ~clk;

  task write_sram(input [AddrSize-1:0] addr, input [DataSize-1:0] data, input logic block_sel);
    @(posedge clk);
    if (!block_sel) begin
      my_calc.sram_A.mem[addr] = data;
    end
    else begin
      my_calc.sram_B.mem[addr] = data;
    end
    calc_driver_h.initialize_sram(addr, data, block_sel);
  endtask
  
  // New task to test reset functionality in different FSM states
  task reset_in_state(input state_t target_state);
    $display("--- Starting reset test for state: %s ---", target_state.name());
    
    // Start a basic calculation to get the FSM running
    fork
        calc_driver_h.start_calc(0, 4, 5, 9);
    join_none

    // Wait until the FSM reaches the target state
    @(posedge clk iff state == target_state);
    $display("Reached target state: %s. Applying reset.", target_state.name());
    
    // Apply reset
    calc_driver_h.reset_task();
    
    // Check if the FSM returned to the IDLE state
    if (state == S_IDLE) begin
      $display("PASS: DUT returned to S_IDLE after reset from %s.", target_state.name());
    end else begin
      $error("FAIL: DUT did NOT return to S_IDLE after reset from %s. Current state is %s.", target_state.name(), state.name());
    end
    
    // Wait a few cycles to stabilize before the next test
    repeat(5) @(posedge clk);
  endtask

  initial begin
    `ifdef VCS
    $fsdbDumpon;
    $fsdbDumpfile("simulation.fsdb");
    $fsdbDumpvars(0, calc_tb_top, "+mda", "+all", "+trace_process");
    $fsdbDumpMDA;
    `endif
    `ifdef CADENCE
    $shm_open("waves.shm");
    $shm_probe("AC");
    `endif

    calc_monitor_h = new(calc_if);
    calc_sb_h = new(calc_monitor_h.mon_box);
    calc_sequencer_h = new();
    calc_driver_h = new(calc_if, calc_sequencer_h.calc_box);
    fork
      calc_monitor_h.main();
      calc_sb_h.main();
    join_none
    
    // Initial SRAM population
    calc_if.reset <= 1;
    for (int i = 0; i < 2 ** AddrSize; i++) begin
      write_sram(i, $random, 0);
      write_sram(i, $random, 1);
    end
    repeat(2) @(posedge clk);
    calc_if.reset <= 0;
    repeat(2) @(posedge clk);
    
    // **************************************************
    // ** NEW: FSM RESET TEST SEQUENCE        **
    // **************************************************
    $display("Starting FSM Reset Testing");
    reset_in_state(S_READ);
    reset_in_state(S_ADD);
    reset_in_state(S_WRITE);
    reset_in_state(S_END);
    $display("Finished FSM Reset Testing");

    // Directed part
    $display("Directed Testing");
    
    // Test case 1 - normal addition
    $display("Test case 1 - normal addition");
    calc_driver_h.start_calc(0, 4, 5, 9);
    @(posedge clk iff (state == S_END));
    repeat(5) @(posedge clk); // Give scoreboard time to check

    // Test case 2 - addition with overflow
    $display("Test case 2 - addition with overflow");
    write_sram(10, 32'hFFFFFFFF, 0);
    write_sram(10, 32'hFFFFFFFF, 1);
    calc_driver_h.start_calc(10, 10, 11, 11);
    @(posedge clk iff (state == S_END));
    repeat(5) @(posedge clk);

    // Test case 3 - single address read/write
    $display("Test case 3 - single address read/write");
    calc_driver_h.start_calc(20, 20, 21, 21);
    @(posedge clk iff (state == S_END));
    repeat(5) @(posedge clk);

    // Test case 4 - Overlapping read and write addresses
    $display("Test case 4 - Overlapping read/write addresses");
    calc_driver_h.start_calc(10, 15, 12, 17); // Read [10:15], Write [12:17]
    @(posedge clk iff (state == S_END));
    repeat(5) @(posedge clk);
    
    // Random part
    $display("Randomized Testing");
    calc_sequencer_h.gen(5); // Generate 5 random transactions
    calc_driver_h.drive();

    //WRITE TO IDLE
    $display("Test reset from READ TO IDLE state");
    fork
      begin: runner
        calc_driver_h.start_calc(.read_start_addr(140), .read_end_addr(143),
         .write_start_addr(270), .write_end_addr(270));
      end
        wait (state == S_WRITE);
    join_any
    calc_if.reset <= 1'b1;
    repeat (2) @(posedge clk);
    assert(state == S_IDLE) else $error("DUT did not return to IDLE state after reset from READ state");
    repeat (10) @(posedge clk);


    repeat (100) @(posedge clk);

    $display("TEST PASSED");
    $finish;
  end

  /********************
      ASSERTIONS
  *********************/
  // Add Assertions
  //RESET: assert property (@(posedge clk) (rst |-> (state == S_IDLE)));
  //VALID_INPUT_ADDRESS: assert property (@(posedge clk) (state == S_READ) |-> (calc_if.curr_rd_addr < (2**AddrSize)));
  // BUFFER_LOC_TOGGLES: assert property (@(posedge clk) (state == S_ADD) |-> ($past(calc_if.loc_sel) != calc_if.loc_sel));

endmodule

