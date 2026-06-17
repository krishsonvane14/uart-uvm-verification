// =============================================================================
// uart_if.sv — UART UVM Testbench Interface
// =============================================================================
// Single connection point between all UVM components and the DUT.
// Bundles every signal needed to drive uart_tx, uart_rx, and uart_regs.
//
// Clocking blocks
//   driver_cb  — output #1 skew for driven signals, input #1 for sampled
//   monitor_cb — all signals are input #1 (monitor never drives)
//
// Modports
//   driver_mp  — driver agent uses driver_cb
//   monitor_mp — monitor agent uses monitor_cb
// =============================================================================
interface uart_if #(
    parameter int CLK_FREQ  = 16_000_000,
    parameter int BAUD_RATE = 100_000
)(
    input logic clk
);

    // -----------------------------------------------------------------------
    // Group 1: UART TX data interface
    // valid/ready handshake into uart_tx.
    // tx_busy reflects the transmitter actively shifting a frame.
    // -----------------------------------------------------------------------
    logic [7:0] tx_data;
    logic       tx_valid;
    logic       tx_ready;
    logic       tx_busy;

    // -----------------------------------------------------------------------
    // Group 2: UART serial lines
    // tx_serial is the raw bit-stream output of uart_tx.
    // rx_serial is the input to uart_rx; tied to tx_serial in tb_top
    // to form a loopback path for self-checking tests.
    // -----------------------------------------------------------------------
    logic tx_serial;
    logic rx_serial;

    // -----------------------------------------------------------------------
    // Group 3: UART RX output
    // rx_valid pulses one cycle when a complete frame has been received.
    // rx_error and rx_parity_err are single-cycle flags, coincident with
    // rx_valid on the cycle the stop bit is sampled.
    // -----------------------------------------------------------------------
    logic [7:0] rx_data;
    logic       rx_valid;
    logic       rx_error;
    logic       rx_parity_err;

    // -----------------------------------------------------------------------
    // Group 4: Register bus
    // CPU-facing interface into uart_regs: 2-bit address, 8-bit data,
    // and single-cycle write/read enable strobes.
    // -----------------------------------------------------------------------
    logic [1:0] reg_addr;
    logic [7:0] reg_wdata;
    logic [7:0] reg_rdata;
    logic       reg_wen;
    logic       reg_ren;

    // -----------------------------------------------------------------------
    // Group 5: Register control outputs
    // Driven by uart_regs and wired into the TX/RX configuration ports.
    // Sampled by the driver to verify RAL-to-DUT register connectivity.
    // -----------------------------------------------------------------------
    logic       tx_en;
    logic       rx_en;
    logic       parity_en;
    logic       parity_type;
    logic [7:0] baud_div;

    // -----------------------------------------------------------------------
    // Group 6: Reset
    // Active-low asynchronous reset, driven by tb_top and the driver agent.
    // -----------------------------------------------------------------------
    logic rst_n;

    // -----------------------------------------------------------------------
    // Clocking block: driver_cb
    // All stimulus is launched #1 before the clock edge (output #1) to
    // satisfy setup time and avoid delta-cycle races.
    // Responses are sampled #1 after the clock edge (input #1) once the
    // DUT outputs have settled.
    // -----------------------------------------------------------------------
    clocking driver_cb @(posedge clk);
        default input #1 output #1;
        output tx_data, tx_valid,
               reg_addr, reg_wdata, reg_wen, reg_ren,
               rst_n;
        input  tx_ready, tx_busy,
               rx_data, rx_valid, rx_error, rx_parity_err,
               reg_rdata,
               tx_en, rx_en, parity_en, parity_type, baud_div;
    endclocking

    // -----------------------------------------------------------------------
    // Clocking block: monitor_cb
    // Passively observes all bus activity; every signal is an input.
    // Sampled #1 after the clock edge for consistent capture.
    // -----------------------------------------------------------------------
    clocking monitor_cb @(posedge clk);
        default input #1;
        input tx_data, tx_valid, tx_ready, tx_busy, tx_serial,
              rx_data, rx_valid, rx_error, rx_parity_err,
              reg_addr, reg_wdata, reg_rdata, reg_wen, reg_ren;
    endclocking

    // -----------------------------------------------------------------------
    // Modports — reference clocking blocks only
    // -----------------------------------------------------------------------
    modport driver_mp  (clocking driver_cb);
    modport monitor_mp (clocking monitor_cb);

endinterface
