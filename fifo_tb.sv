`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 07/27/2025 04:56:01 PM
// Design Name: Verification of a FIFO
// Module Name: fifo_tb
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////

// Code your design here

// Code your testbench here
// or browse Examples
class transaction;
  
  rand bit oper;
  bit wr,rd;
  bit full,empty;
  bit [7:0]data_in;
  bit [7:0]data_out;
  
  constraint oper_cntrl{
    oper dist {1:/50 , 0:/50};
  }
  
endclass

///////////////////////////////////////////////////////////////////

class generator;
  
  transaction tr;
  mailbox #(transaction) g2d;
  
  event next; //know when to send next transaction
  event done; //conveys completion of sending stimulus
  
  int count=0; //sending count no. of times stimulus to design
  int i=0; //keep count of no of stimulus sent to design
  
  function new(mailbox #(transaction) g2d);
    this.g2d=g2d;
    tr=new();
  endfunction
  
  task run();
    repeat(count)
      begin
        assert(tr.randomize()) else $error("Randomization unsuccessful");
        i++;
        g2d.put(tr);
        $display("[GEN]: Oper:%0d iteration: %0d",tr.oper,i);
        @(next); //wait till scoreboard completes its operation before we generate new stimuli
      end
    ->done; //trigger completion of stimulus generation
  endtask
endclass

////////////////////////////////////////////////////////////////
class driver;
  
transaction dc;
  mailbox #(transaction) g2d;
  
  virtual fifo_if fif;
  
  
  function new(mailbox #(transaction) g2d);
    this.g2d=g2d;
  endfunction
  
  //reset DUT
  task reset();
  fif.rst<= 1'b1;
  fif.rd<= 1'b0;
  fif.wr<= 1'b1;
  fif.data_in<= 0;
  repeat(5) @(posedge fif.clk);
  fif.rst<= 1'b0;
  $display("[DRV]: DUT RESET DONE");
  $display("---------------------------------------------------------------------");
  endtask
  
  
  task write();
   @(posedge fif.clk);
   fif.rst<=1'b0;
   fif.rd<=1'b0;
   fif.wr<= 1'b1;
   fif.data_in<= $urandom_range(1,50);
    @(posedge fif.clk);
    fif.wr<= 1'b0;
    $display("[DRV]: DATA WRITE data: %0d",fif.data_in);
    @(posedge fif.clk);
  endtask
  
  
  
  task read();
  @(posedge fif.clk);
   fif.rst<=1'b0;
   fif.wr<=1'b0;
   fif.rd<= 1'b1;
   @(posedge fif.clk);
   fif.rd<=1'b0;
    $display("[DRV] DATA READ"); 
    @(posedge fif.clk);
  endtask
  
  task run();
    forever begin
      g2d.get(dc);
      if(dc.oper ==1)
        write();
      else
        read();
    end
  endtask
  
endclass

/////////////////////////////////////////////////////

class monitor;
  
  virtual fifo_if fif;
  mailbox #(transaction) m2s;
  transaction t;
  
  function new(mailbox #(transaction)m2s);
    this.m2s=m2s;
  endfunction
  
  task run();
    t=new();
    
    forever begin
      repeat(2) @(posedge fif.clk);
      t.wr = fif.wr;
      t.rd = fif.rd;
      t.data_in = fif.data_in;
      t.full = fif.full;
      t.empty = fif.empty;
      @(posedge fif.clk);
      t.data_out = fif.data_out;
      
      m2s.put(t);
      $display("[MON]: wr: %0d, rd:%0d, full:%0d, empty:%0d, data_in:%0d, data_out:%0d",t.wr,t.rd,t.full,t.empty,t.data_in,t.data_out);
    end
  endtask
endclass

//////////////////////////////////////////////////////////

class scoreboard;
  
  mailbox #(transaction) m2s;
  transaction t;
  event next;
  
  bit[7:0] din[$];
  bit [7:0] temp;
  int err=0;
  
  function new(mailbox #(transaction)m2s);
    this.m2s=m2s;
  endfunction
  
  
  task run();
    forever begin
      m2s.get(t);
      
      $display("[SCO]: wr:%0d, rd=%0d, empty=%0d, full=%0d, data_in=%0d, data_out=%0d",t.wr,t.rd,t.empty,t.full,t.data_in,t.data_out);
      
      if(t.wr==1'b1);
      begin
        if(t.full==1'b0)
          begin
            din.push_front(t.data_in);
            $display("[SCO]: DATA STORED IN QUEUE:%0d",t.data_in);
          end
        else
          begin
            $display("[SCO]: FIFO IS FULL");
          end
        $display("-----------------------------------------------");
      end
      
      if(t.rd==1'b1)
        begin
          if(t.empty==1'b0)
            begin
              temp=din.pop_back();
              if(t.data_out == temp)
              $display("[SCO]: DATA MATCH");
              else begin
                $error("[SCO]: DATA MISMATCH");
                err++;
              end
            end
          else
            begin
              $display("[SCO]: FIFO IS EMPTY");
            end
        end
      $display("----------------------");
    end
    
    ->next;
  endtask
  
endclass
      
////////////////////////////////////////////////////////
class environment;
  
generator gen;
driver drv;
monitor mon;
scoreboard sco;
  
  mailbox #(transaction) g2d; //generator to driver
  mailbox #(transaction) m2s; //monitor to scoreboard
  
  virtual interface fifo_if fif;
  event e;
    
    function new(virtual fifo_if fif);
      g2d= new();
      m2s= new();
      gen =new(g2d);
      drv= new(g2d);
      
      mon=new(m2s);
      sco= new(m2s);
      
      this.fif = fif;
      drv.fif =this.fif;
      mon.fif = this.fif;
      
      gen.next =e;
      sco.next=e;
    endfunction
    
    task pre_test();
      drv.reset();
    endtask
    
    task test();
      fork
        gen.run();
        drv.run();
        mon.run();
        sco.run();
      join_any
    endtask
    
    task post_test();
      wait(gen.done.triggered);
      $display("---------------------------------------------------");
      $display("Error count:%0d",sco.err);
       $display("---------------------------------------------------");
      $finish();
    endtask
    
    task run();
      pre_test();
      test();
      post_test();
    endtask
    endclass
    
    
  //////////////////////////////////////////////////////////////////////////////
    
   module fifo_tb;
     
     fifo_if fif();
     
     FIFO dut(fif.clk, fif.rd, fif.wr,fif.data_in,fif.data_out,fif.empty, fif.full,fif.rst);
     
     initial begin
       fif.clk<=0;
     end
     
     always #10 fif.clk<= ~fif.clk;
     environment env;
     
     initial begin
       env=new(fif);
       env.gen.count = 10;
       env.run();
     end
     
     initial begin
       $dumpfile("dump.vcd");
       $dumpvars;
     end
   endmodule
     
     
     
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
      
      
      
   


























        
        
        
        
        
        
        
        
    
    
    
    
    
    
    
    
    
    
    
