class calc_sb #(int DataSize, int AddrSize);




  // Signals needed for the golden model implementation in the scoreboard
  int mem_a [2**AddrSize];
  int mem_b [2**AddrSize];
  logic second_read = 0;
  int golden_lower_data;
  int golden_upper_data;
  mailbox #(calc_seq_item #(DataSize, AddrSize)) sb_box;




  function new(mailbox #(calc_seq_item #(DataSize, AddrSize)) sb_box);
    this.sb_box = sb_box;
  endfunction




  task main();
    calc_seq_item #(DataSize, AddrSize) trans;
    forever begin
      sb_box.get(trans);
   if (trans.initialize) begin // only do this if initialization is on,
    if (!trans.loc_sel) begin // if loc sel is 0 then do lower/A
      mem_a[trans.curr_wr_addr] = trans.lower_data; // puts memory as from the trans
    end else begin
      mem_b[trans.curr_wr_addr] = trans.upper_data;
    end
      $display($stime, "SB initialized SRAM %s at Addr 0x%0x with Dut value %s",
      !trans.loc_sel ? "A" : "B",
      trans.curr_wr_addr,
      !trans.loc_sel ? trans.lower_data : trans.upper_data);
    end
    // reading




    if(!trans.rdn_wr && !trans.initialize) begin
      if (!second_read) begin
        golden_lower_data = mem_a[trans.curr_rd_addr];
        golden_upper_data = mem_b[trans.curr_rd_addr];
        second_read = 1;
      end else begin
        if (trans.lower_data !== golden_lower_data) begin
          $error("Read mismatch Sram A at Addr 0x%0x, dut reading: 0x%0x, but expected is 0x%x",
          trans.curr_rd_addr, trans.lower_data, golden_lower_data);
          $finish;
        end
         if (trans.upper_data !== golden_upper_data) begin
          $error("Read mismatch Sram A at Addr 0x%0x, dut reading: 0x%0x, but expected is 0x%x",
          trans.curr_rd_addr, trans.upper_data, golden_upper_data);
          $finish;
         end
         $display($stime, "SB: Read verified at addr 0x%0x", trans.curr_rd_addr);
         second_read = 0;
      end
    end
    if (trans.rdn_wr && !trans.initialize) begin
      if (trans.lower_data !== golden_lower_data) begin
        $error("Mismatch");
        $finish; // fill out later
    end
    if (trans.upper_data !== golden_upper_data) begin
      $error("mismatch");
      $finish; // fill out later
    end
    mem_a[trans.curr_wr_addr] = trans.lower_data;
    mem_b[trans.curr_wr_addr] = trans.upper_data;
    $display($stime, "SB: write verified at addr 0x%0x", trans.curr_wr_addr);
    end
    end








   
  endtask




endclass : calc_sb


