// =============================================================================
// uart_rx.sv — UART Receiver with configurable oversampling
// =============================================================================
module uart_rx #(
    parameter int CLK_FREQ    = 50_000_000,  // Hz
    parameter int BAUD_RATE   = 9_600,       // bps
    parameter int DATA_BITS   = 8,
    parameter bit PARITY_EN   = 1'b1,
    parameter bit PARITY_TYPE = 1'b0,        // 0=even, 1=odd
    parameter int OVERSAMPLE  = 16           // 1 or 16
)(
    input  logic                  clk,
    input  logic                  rst_n,
    // Serial input
    input  logic                  rx_serial,
    // Data output
    output logic [DATA_BITS-1:0]  rx_data,
    output logic                  rx_valid,     // pulses 1 cycle when frame complete
    output logic                  rx_error,     // framing error (bad stop bit)
    output logic                  rx_parity_err // parity mismatch
);

    // -----------------------------------------------------------------------
    // Derived timing parameters
    //
    // SAMPLE_MID: 0-indexed oversample tick at which to sample (midpoint).
    // The naive formula (OVERSAMPLE/2)-1 evaluates to -1 when OVERSAMPLE=1
    // (integer division: 1/2=0, 0-1=-1), making baud_tick comparison always
    // false and causing the receiver to silently drop all frames.
    // Guard: for OVERSAMPLE=1 the only valid sample point is tick 0.
    // -----------------------------------------------------------------------
    localparam int BAUD_DIV   = CLK_FREQ / BAUD_RATE;
    localparam int SAMPLE_DIV = BAUD_DIV / OVERSAMPLE;
    localparam int SAMPLE_MID = (OVERSAMPLE > 1) ? (OVERSAMPLE / 2) - 1 : 0;

    // Safe counter widths — $clog2(1)==0 produces an invalid [-1:0] range.
    // For any value ≤1 the counter needs exactly 1 bit (holds only 0).
    localparam int SMPL_CNT_W = (SAMPLE_DIV > 1) ? $clog2(SAMPLE_DIV) : 1;
    localparam int OS_CNT_W   = (OVERSAMPLE  > 1) ? $clog2(OVERSAMPLE) : 1;
    localparam int BIT_CNT_W  = (DATA_BITS   > 1) ? $clog2(DATA_BITS)  : 1;

    // -----------------------------------------------------------------------
    // State encoding
    // -----------------------------------------------------------------------
    typedef enum logic [2:0] {
        IDLE   = 3'b000,
        START  = 3'b001,
        DATA   = 3'b010,
        PARITY = 3'b011,
        STOP   = 3'b100
    } state_t;

    state_t state;

    // -----------------------------------------------------------------------
    // Input synchronizer — 2-FF chain prevents metastability propagation.
    // rx_serial originates outside the local clock domain; both FFs reset
    // to 1'b1 (the UART idle / mark level).
    // -----------------------------------------------------------------------
    logic rx_meta, rx_sync;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_meta <= 1'b1;
            rx_sync <= 1'b1;
        end else begin
            rx_meta <= rx_serial;
            rx_sync <= rx_meta;
        end
    end

    // -----------------------------------------------------------------------
    // Internal timing signals
    // -----------------------------------------------------------------------
    logic [SMPL_CNT_W-1:0] sample_cnt;
    logic                   sample_tick;  // pulses every SAMPLE_DIV clocks

    logic [OS_CNT_W-1:0]   os_cnt;
    logic                   baud_tick;    // pulses at SAMPLE_MID (midpoint sample)
    logic                   bit_done;     // pulses at OVERSAMPLE-1 (end of bit period)

    // -----------------------------------------------------------------------
    // Data path signals
    // -----------------------------------------------------------------------
    logic [DATA_BITS-1:0]  shift_reg;
    logic [BIT_CNT_W-1:0]  bit_cnt;
    logic                   parity_calc;  // running XOR accumulator
    logic                   parity_rcvd;  // parity bit captured from line

    // -----------------------------------------------------------------------
    // Parity match — combinational decode from stable registered values.
    // Both parity_calc (last updated in DATA) and parity_rcvd (last updated
    // in PARITY) are settled by the time STOP samples the stop bit.
    // -----------------------------------------------------------------------
    logic parity_match;
    always_comb begin
        parity_match = (parity_calc == parity_rcvd);
    end

    // -----------------------------------------------------------------------
    // Stage 1: sample tick generator
    // Divides clk by SAMPLE_DIV; resets while in IDLE so the first tick
    // after entering START is always a complete SAMPLE_DIV period.
    // -----------------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sample_cnt  <= '0;
            sample_tick <= 1'b0;
        end else if (state == IDLE) begin
            sample_cnt  <= '0;
            sample_tick <= 1'b0;
        end else begin
            if (sample_cnt == SAMPLE_DIV - 1) begin
                sample_cnt  <= '0;
                sample_tick <= 1'b1;
            end else begin
                sample_cnt  <= sample_cnt + 1'b1;
                sample_tick <= 1'b0;
            end
        end
    end

    // -----------------------------------------------------------------------
    // Stage 2: oversample counter
    // Counts sample_ticks within each bit period.
    //   baud_tick — fires at SAMPLE_MID: midpoint of the bit, best SNR
    //   bit_done  — fires at OVERSAMPLE-1: signals end of the bit period
    //
    // OVERSAMPLE=16: SAMPLE_MID=7  → baud_tick mid-bit, bit_done 8 ticks later
    // OVERSAMPLE=1:  SAMPLE_MID=0  → baud_tick and bit_done coincide each tick
    // -----------------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            os_cnt    <= '0;
            baud_tick <= 1'b0;
            bit_done  <= 1'b0;
        end else if (state == IDLE) begin
            os_cnt    <= '0;
            baud_tick <= 1'b0;
            bit_done  <= 1'b0;
        end else if (sample_tick) begin
            baud_tick <= (os_cnt == SAMPLE_MID);
            bit_done  <= (os_cnt == OVERSAMPLE - 1);
            if (os_cnt == OVERSAMPLE - 1)
                os_cnt <= '0;
            else
                os_cnt <= os_cnt + 1'b1;
        end else begin
            baud_tick <= 1'b0;
            bit_done  <= 1'b0;
        end
    end

    // -----------------------------------------------------------------------
    // Main state machine
    // -----------------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state         <= IDLE;
            rx_data       <= '0;
            rx_valid      <= 1'b0;
            rx_error      <= 1'b0;
            rx_parity_err <= 1'b0;
            shift_reg     <= '0;
            bit_cnt       <= '0;
            parity_calc   <= PARITY_TYPE;
            parity_rcvd   <= 1'b0;
        end else begin
            // Default: pulse outputs are 0 every cycle
            rx_valid      <= 1'b0;
            rx_error      <= 1'b0;
            rx_parity_err <= 1'b0;

            case (state)

                // -------------------------------------------------------------
                // IDLE: hold parity seed fresh; wait for start-bit low
                // -------------------------------------------------------------
                IDLE: begin
                    bit_cnt     <= '0;
                    parity_calc <= PARITY_TYPE;
                    if (!rx_sync) begin
                        state <= START;
                    end
                end

                // -------------------------------------------------------------
                // START: glitch filter at midpoint; advance to DATA at bit_done
                //
                // else-if gives the glitch-abort priority over bit_done.
                // This is critical for OVERSAMPLE=1 where both baud_tick and
                // bit_done assert in the same cycle (SAMPLE_MID == OVERSAMPLE-1 == 0).
                // Without the else, the bit_done branch would overwrite
                // state<=IDLE and incorrectly advance to DATA on a noise pulse.
                // -------------------------------------------------------------
                START: begin
                    if (baud_tick && rx_sync) begin
                        state <= IDLE;          // false start — line returned high
                    end else if (bit_done) begin
                        state <= DATA;
                    end
                end

                // -------------------------------------------------------------
                // DATA: sample at midpoint; advance bit_cnt at bit_done
                // Shift into MSB so that LSB-first serial data ends up at [0]:
                //   Bit 0 received → lands at shift_reg[0] after 8 right-shifts
                // -------------------------------------------------------------
                DATA: begin
                    if (baud_tick) begin
                        shift_reg   <= {rx_sync, shift_reg[DATA_BITS-1:1]};
                        parity_calc <= parity_calc ^ rx_sync;
                    end
                    if (bit_done) begin
                        if (bit_cnt == DATA_BITS - 1) begin
                            bit_cnt <= '0;
                            state   <= PARITY_EN ? PARITY : STOP;
                        end else begin
                            bit_cnt <= bit_cnt + 1'b1;
                        end
                    end
                end

                // -------------------------------------------------------------
                // PARITY: latch received parity bit; parity_match evaluates
                // combinationally on the following cycle once parity_rcvd settles
                // -------------------------------------------------------------
                PARITY: begin
                    if (baud_tick) begin
                        parity_rcvd <= rx_sync;
                    end
                    if (bit_done) begin
                        state <= STOP;
                    end
                end

                // -------------------------------------------------------------
                // STOP: sample stop bit; output data and error flags; return idle
                //
                // Framing error takes priority over parity error — if the stop
                // bit is wrong the parity bit may have been mis-sampled too.
                // rx_parity_err only asserts on an otherwise-valid frame.
                // -------------------------------------------------------------
                STOP: begin
                    if (baud_tick) begin
                        rx_data  <= shift_reg;
                        rx_valid <= 1'b1;
                        if (!rx_sync) begin
                            rx_error <= 1'b1;
                        end else if (PARITY_EN && !parity_match) begin
                            rx_parity_err <= 1'b1;
                        end
                    end
                    if (bit_done) begin
                        state <= IDLE;
                    end
                end

                default: state <= IDLE;

            endcase
        end
    end

endmodule
