-------------------------------------------------------
--! @file
--! @brief RFM12B Phy component
--! @author Dominik Meyer
--! @email dmeyer@hsu-hh.de
--! @date 2017-01-27
--! @copyright 2017 by Dominik Meyer, License GPLv2
-------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;
use ieee.numeric_std.all;

library work;
use work.RFM12B_PKG.all;

--! @page RFM12B_PHY_PM RFM12B_PHY Power Management
--!
--! This page describes the different power management modes of the RFM12B_PHY component.
--! They are *not* identical to the power management modes of the RFM12B!
--!
--! \li 00 - standard operating mode, RFM12B receiver is enabled and the PHY is reading the status word
--!          every 200ms to check for a free transmission channel. This mode is also required if only
--!          transmission should be used because the receiver is required for checking of channel availability
--! \li 01 - receiver only mode, RFM12B receiver is enabled and the PHY only reacts on incoming interrupts
--!          from the RFM12B. \b no polling of the status word happens
--! \li 10 - full shutdown - Receiver and Transmitter are off, \b no polling, \bno interrupts. PHY reinitializes the
--!          RFM12B if the power mode is changed
--! \li 11 - reserved



--! RFM12B Phy component


--! The RFM12B_PHY is responsible for receiving and transmitting one byte through the RFM12B
--! The operating mode of the RFM12B is configurable through the generics
--! \image html RFM12BPHY.png
entity RFM12B_PHY is
  generic(
    GEN_SysClockinHz      : integer                       := 200000000;   --! the system clock frequency in Hz
    GEN_PowerUpWatchdog   : integer                       := 10;          --! reset the chip after this number of ms if no PoR has been received after reset
    GEN_ReceiverWatchdog  : integer                       := 10;          --! reset the chip after this number of ms if no Data Available interrupt has been received
    -- general configuration command values
    GEN_EL                : std_logic                     := '1';        --! enable internal data register (only '1' is supported at the moment)
    GEN_EF                : std_logic                     := '1';        --! enable fifo mode (only '1' is supported at the moment)
    GEN_BASEBAND          : integer                       := 868;        --! which baseband to use
    GEN_CRYSTAL_LOAD      : std_logic_vector(3 downto 0)  := "0111";     --! the crystal load capacity of used crystal (choose according to datasheet)

    -- power management configuration
    GEN_DC                : std_logic                     := '1';        --! Disable Clock output to microcontroller
    -- frequency configuration
    GEN_FREQUENCY         : integer                       := 868000000;  --! the frequency the RFM12B should work at in Hz
    -- datarate configuration
    GEN_DATARATE          : integer                       := 9600;       --! the datarate the RFM12B should use
    -- receiver configuration
    GEN_VDI_ENABLE        : std_logic                     := '1';        --! use VDI/INTn as valid data input, false = interrupt
    GEN_VDI_SPEED         : std_logic_vector(1 downto 0)  := "11";       --! 00=fast, 01=medium, 10=slow, 11=always high
    GEN_RECV_BANDWIDTH    : std_logic_vector(2 downto 0)  := "001";      --! 000=reserved, 001=400kHz, 010=340kHz, 011=270kHz,
                                                                         --! 100=200kHz, 101=134kHz, 110=67kHz, 111=reserved
    GEN_GAIN              : std_logic_vector(1 downto 0)  := "01";       --! Gain of incoming signal, 00=0dB, 01=-6dB, 10=-14dB, 11=-20dB
    GEN_RSSI              : std_logic_vector(2 downto 0)  := "100";      --! 000=-103dB, 001=-97dB, 010=-91dB, 011=-86dB, 100=-79dB, 101=-73dB, 11x=reserved
    -- data filter configuration
    GEN_AUTOLOCK          : std_logic                     := '1';        --! switch to slow mode automatically if clock is identified 1=on,0=off
    GEN_LOCK_MODE         : std_logic                     := '1';        --! slow and fast mode. 0=slow, 1=fast
    GEN_DATAFILTER_TYPE   : std_logic                     := '0';        --! 0 = digital, 1=analog
    GEN_QUALITY           : std_logic_vector(2 downto 0)  := "011";      --! threshhold for data signal quality 000=always on, 100=medium, 111=maximum
    -- fifo and reset configuration
    GEN_FIFO_INTERRUPT    : std_logic_vector(3 downto 0)  := "1000";     --! after receiving how many bits issue interrupt 0000=reserved, 0001 at each bit, 1000 8th bit, 1111=15th bit
    GEN_FIFO_START        : std_logic                     := '0';        --! when to start filling the fifo, 0 after sync pattern, 1 always
    GEN_SYNC_PATTERN_LEN  : std_logic                     := '0';        --! 0=2byte, 1=1byte
    GEN_DIS_SENSE_RESET   : std_logic                     := '1';        --! disable sensitive PoR, 0=active, 1=deactive
    -- sync bytes configuration
    GEN_SYNC_BYTE         : std_logic_vector(7 downto 0)  := x"D4";      --! synchronization byte D4  = standard
    -- automatic frequency control configuration
    GEN_AFC_MODE          : std_logic_vector(1 downto 0)  := "10";       --! 00 = no auto, 01=one time after PoR, 10 as long as VDI high, 11=independent (not working correctly)
    GEN_AFC_RANGE_LIMIT   : std_logic_vector(1 downto 0)  := "10";       --! correction range 00=-64 - +63, 01=-16 - +15, 10=-8 - +7, 11=-4-+3
    GEN_AFC_FINE_MODE     : std_logic                     := '1';        --! fine calculation mode, but slower
    GEN_AFC_OFFSET_ENABLE : std_logic                     := '1';        --! 1 = OFFSET register enable, 0 = OFFSET register disable
    GEN_AFC_ENABLE        : std_logic                     := '1';        --! 1 = enable AFC calculation
    -- transmitter configuration
    GEN_MP                : std_logic                     := '0';
    GEN_P                 : std_logic_vector(2 downto 0)  := "000";
    GEN_M                 : integer                       := 125000
      );
  port (
    -- user interface
    idData          :  in std_logic_vector( 7 downto 0);                 --! Data input for transmitting one byte
    icFrame         :  in std_logic;                                     --! idenitifies one frame. at each clock tick this is high, one byte has to be present at idData
    icWe            :  in std_logic;                                     --! write idData
    ocChannelFree   : out std_logic;                                     --! signals that the channel is free for a transmission

    odData          : out std_logic_vector( 7 downto 0);                 --! Data Output for received bytes
    ocValid         : out std_logic;                                     --! Signals validity of odData
    idFrameLength   :  in std_logic_vector( 7 downto 0);                 --! the RFM12B Fifo has to be restarted after each frame, to reduce latency the length of the frame can be given here

    icPowerMode     :  in std_logic_vector( 1 downto 0);                 --! Power Mode of the PHY \sa \ref RFM12B_PHY_PM RFM12B_PHY Power Modes

    -- RFM12B Interface                                           --! the interface signals to connect to the RFM12B
    odSDI           : out std_logic;
    idSDO           :  in std_logic;
    oSCLK           : out std_logic;
    ocSELn          : out std_logic;
    icINTn          :  in std_logic;
    ocResetN        : out std_logic;


    -- System interface
    iClk            :  in std_logic;                              --! standard system clock
    iClkEn          :  in std_logic;                              --! Active high clock enable signal
    iReset          :  in std_logic                               --! Active high clock synchronous reset signal
  );
end RFM12B_PHY;

architecture arch of RFM12B_PHY is
  component RFM12B_SPI
    generic (
      GEN_SysClockinHz : integer := 200000000;
      GEN_SPI_ClockinHz: integer :=   2000000
    );
    port (
      ocReady       : out std_logic;
      idInstruction : in  std_logic_vector(15 downto 0);
      icWe          : in  std_logic;
      odData        : out std_logic_vector(15 downto 0);
      ocValid       : out std_logic;
      ocINT         : out std_logic;
      icReset       :  in std_logic;
      odSDI         : out std_logic;
      idSDO         : in  std_logic;
      oSCLK         : out std_logic;
      ocSELn        : out std_logic;
      icINTn        : in  std_logic;
      ocResetN      : out std_logic;
      iClk          : in  std_logic;
      iClkEn        : in  std_logic;
      iReset        : in  std_logic                               --! Active high clock synchronous reset signal
    );
  end component RFM12B_SPI;

  --
  -- some standard RFM12B commands
  --
  constant c_RFM12B_SLEEP         : std_logic_vector(15 downto 0) := x"82" & "0000000" & GEN_DC;
  constant c_RFM12B_RECV_ON       : std_logic_vector(15 downto 0) := x"82" & "1100100" & GEN_DC;
  constant c_RFM12B_RECV_OFF      : std_logic_vector(15 downto 0) := x"82" & "0100100" & GEN_DC;
  constant c_RFM12B_TRANS_ON      : std_logic_vector(15 downto 0) := x"82" & "0110100" & GEN_DC;
  constant c_RFM12B_CLEAR_FIFO    : std_logic_vector(15 downto 0) := x"CA" & GEN_FIFO_INTERRUPT & '0' & GEN_FIFO_START & '0' & GEN_DIS_SENSE_RESET;
  constant c_RFM12B_ENABLE_FIFO   : std_logic_vector(15 downto 0) := x"CA" & GEN_FIFO_INTERRUPT & '0' & GEN_FIFO_START & '1' & GEN_DIS_SENSE_RESET;

  --
  -- initialization sequence for RMF12B
  --

  --! type declaration for RFM12B initialization sequence
  type t_init is array (0 to 11) of std_logic_vector(15 downto 0);

  --! RFM12B initialization sequence
  signal init : t_init := (
    x"80" & GEN_EL & GEN_EF & f_RFM12_BASEBAND(GEN_BASEBAND) & GEN_CRYSTAL_LOAD,            --! configuration setting command
    c_RFM12B_SLEEP,                                                                         --! set device to sleep
    x"A" & f_RFM12_FREQUENCY_CALC(GEN_BASEBAND, GEN_FREQUENCY),                             --! set communication frequency
    x"C6" & f_RFM12_DATARATE_CALC(GEN_DATARATE),                                            --! set the datarate
    x"9" & '0' & GEN_VDI_ENABLE & GEN_VDI_SPEED & GEN_RECV_BANDWIDTH & GEN_GAIN & GEN_RSSI, --! Receiver configuration
    x"C2" & GEN_AUTOLOCK & GEN_LOCK_MODE & '1' & GEN_DATAFILTER_TYPE & '1' & GEN_QUALITY,   --! Datafilter configuration
    c_RFM12B_CLEAR_FIFO,                                                                    --! Clear and deactivate fifo
    x"C4" & GEN_AFC_MODE & GEN_AFC_RANGE_LIMIT & '0' & GEN_AFC_FINE_MODE & GEN_AFC_OFFSET_ENABLE & GEN_AFC_ENABLE, --! AFC configuration
    "1001100" & GEN_MP & f_RFM12_TXCONF_FS_CALC(GEN_M) & '0' & GEN_P,                                            --! transmitter configuration
    --x"9870",
    x"C800",                                                                                --! deactivate low dutycycle
    x"E000",                                                                                --! deactivate wakeup timer
    x"0000"                                                                                 --! reset possible existing interrupts
  );

  constant c_init_length  : integer := 12;                                                  --! length of the RFM12B initialization sequence

  -- Some Counters and Registers
  --
  signal srCounter          : integer := 0;
  signal srDelayCounter     : integer := 0;
  signal srReceivedCounter  : integer range 0 to 19 := 0;

  signal srStatus       : std_logic_vector(15 downto 0);
  signal srStatusNew    : std_logic;
  signal srStatusUpdate : std_logic;
  signal srWriteDebug   : std_logic_vector( 7 downto 0);
  signal srPoweredUP    : std_logic;
  signal srINT          : std_logic;
  signal scINTenable    : std_logic;
  signal srTransmitBuf  : std_logic_vector( 7 downto 0);

  --
  -- FSM
  --
  type t_states is (st_start, st_reset, st_idle, st_init, st_delay_200, st_delay_200_wait, st_read_status, st_read_data,
                    st_clear_fifo, st_accept_data, st_wait, st_sleep, st_transmit_wait, st_transmit, st_transmit_on);

  signal srCurrentState : t_states;
  signal srNextState    : t_states;


  --
  -- signals for connecting the RFM12B_SPI
  --
  signal scRFM12Bready        : std_logic;
  signal scRFM12BdataValid    : std_logic;
  signal sdRFM12Binstruction  : std_logic_vector(15 downto 0);
  signal scRFM12Bwe           : std_logic;
  signal scRFMint             : std_logic;
  signal sdRFM12Bdata         : std_logic_vector(15 downto 0);
  signal scRFM12Breset        : std_logic;


begin

  --! RFM12B_SPI instance to communicate with the RFM12B chip
  RFM12B_i : RFM12B_SPI
  generic map (
    GEN_SysClockinHz => GEN_SysClockinHz,
    GEN_SPI_ClockinHz=>    1000000        --! run at 2Mhz
  )
  port map (
    ocReady       => scRFM12Bready,
    idInstruction => sdRFM12Binstruction,
    icWe          => scRFM12Bwe,
    odData        => sdRFM12Bdata,
    ocValid       => scRFM12BdataValid,
    ocINT         => scRFMint,
    icReset       => scRFM12Breset,
    odSDI         => odSDI,
    idSDO         => idSDO,
    oSCLK         => oSCLK,
    ocSELn        => ocSELn,
    icINTn        => icINTn,
    ocResetN      => ocResetN,
    iClk          => iClk,
    iClkEn        => '1',
    iReset        => iReset
  );

  --!
  ocChannelFree   <= '1' when srCurrentState=st_idle and icWe='0' and srINT='0' and srStatus(8)='0' else
                     '1' when srCurrentState = st_transmit and srINT='1' and icWe='0' else '0';


  --! RFM12B interrupt processing

  --! sets the srINT signal to icINT als long as iClkEn and scINTenable are high.
  --! scINTenable = '0' resets and disables the interrupt processing
  interrupts: process(iClk)
  begin
    if (rising_edge(iClk)) then
      if (iReset='1') then
        srINT       <= '0';
      elsif(iClkEn='1') then
        if (scINTenable='1') then
          srINT     <= scRFMint;
        else
          srINT     <= '0';
        end if;
      end if;
    end if;
  end process;


  --! FSM for receive and transmit

  --! The FSM uses the signal srCurrentState for identifying its current state
  --! some states support setting the srNextState before transitioning in this
  --! state and returning to srNextState. An example is the st_wait state.
  fsm:process(iClk)
  begin
    if (rising_edge(iClk)) then
      if (iReset = '1') then
        sdRFM12Binstruction   <= (others => '0');
        scRFM12Bwe              <= '0';

        ocValid           <= '0';

        srCounter         <= 0;
        srDelayCounter    <= 0;
        srReceivedCounter <= 0;

        srStatus          <= (others => '0');
        srStatusNew       <= '0';
        srWriteDebug      <= (others => '0');
        srStatusUpdate    <= '0';
        srPoweredUP       <= '0';
        scINTenable       <= '1';
        scRFM12Breset     <= '1';
        srTransmitBuf     <= (others => '0');

        srNextState       <= st_idle;
        srCurrentState    <= st_start;

      elsif (iClkEn = '1') then

        scRFM12Bwe            <= '0';
        scRFM12Breset         <= '0';
        ocValid         <= '0';

        case srCurrentState is

          when st_start       =>  --! initialize and wait for SPI Connection to become ready
                                  srCurrentState    <= st_start;
                                  scRFM12Breset           <= '1';
                                  if (scRFM12Bready='1') then
                                    srPoweredUP     <= '0';
                                    srCounter       <=  0;
                                    scINTenable     <= '1';
                                    scRFM12Breset         <= '1';
                                    srNextState     <= st_idle;
                                    srCurrentState  <= st_delay_200;
                                  end if;

          when st_delay_200   =>
                                  srDelayCounter  <= GEN_SysClockinHz/1000*200;

                                  srCurrentState  <= st_delay_200_wait;

          when st_delay_200_wait =>
                                  srCurrentState  <= st_delay_200_wait;
                                  srDelayCounter  <= srDelayCounter - 1;

                                  if (srDelayCounter=0) then
                                    srCurrentState  <= srNextState;
                                  end if;

          when st_reset       =>
                                srCurrentState      <= st_reset;
                                scRFM12Breset             <= '1';

                                if (srCounter >= GEN_SysClockinHz/1000*1000) then
                                  scRFM12Breset           <= '0';
                                  srCounter         <= 0;
                                  scINTenable       <= '1';
                                  srCurrentState    <= st_idle;
                                end if;

          when st_init        =>
                                srCurrentState      <= st_wait;
                                srNextState         <= st_init;

                                if (scRFM12Bready='1' and srCounter < c_init_length) then
                                  srCounter       <= srCounter + 1;
                                  sdRFM12Binstruction   <= init(srCounter);
                                  scRFM12Bwe            <= '1';
                                elsif(srCounter = c_init_length and scRFM12Bready='1') then
                                  srPoweredUP     <= '1';
                                  srCounter       <= 0;
                                  sdRFM12Binstruction     <= c_RFM12B_RECV_ON;
                                  scRFM12Bwe              <= '1';
                                  srStatusUpdate    <= '1';

                                  srNextState     <= st_clear_fifo;
                                  srCurrentState  <= st_wait;

                                end if;

          when st_idle        =>
                                srCurrentState    <= st_idle;

                                if (srPoweredUP = '0') then
                                  srCounter       <= srCounter + 1;

                                  if (srCounter >= GEN_SysClockinHz/1000*GEN_PowerUpWatchdog) then
                                    srCounter       <= 0;
                                    scRFM12Breset         <= '1';

                                    srCurrentState  <= st_reset;
                                  end if;

                                end if;

                                if (srPoweredUP = '1') then
                                  srCounter       <= srCounter + 1;

                                  if (srCounter mod (GEN_SysClockinHz/1000)*200=0 and icPowerMode="00") then
                                    sdRFM12Binstruction     <= x"0000";
                                    scRFM12Bwe              <= '1';
                                    srCounter               <= 0;

                                    srCurrentState    <= st_read_status;

                                  end if;

                                end if;

                                if (srINT = '1') then
                                  sdRFM12Binstruction     <= x"0000";
                                  scRFM12Bwe              <= '1';
                                  scINTenable       <= '0';
                                  srNextState       <= st_idle;
                                  srCurrentState    <= st_read_status;
                                end if;

                                if (icFrame='1' and icWe='1' and srINT='0' and srStatusNew='0' and srStatus(8)='0') then
                                  scINTenable         <= '1';
                                  sdRFM12Binstruction <= c_RFM12B_RECV_OFF;
                                  scRFM12Bwe          <= '1';
                                  srTransmitBuf       <= idData;

                                  srNextState         <= st_transmit_on;
                                  srCurrentState      <= st_wait;
                                elsif (srStatusNew = '1') then
                                  if (srStatus(14)='1' or (srStatus(15)='1' and srPoweredUP='0')) then
                                    srStatus(14)    <= '0';
                                    srStatus        <= (others => '0');
                                    srStatusNew     <= '0';
                                    srCounter       <= 0;
                                    srNextState     <= st_init;
                                    srCurrentState  <= st_delay_200;
                                  elsif(srReceivedCounter = idFrameLength) then
                                    srReceivedCounter <= 0;
                                    srCurrentState    <= st_clear_fifo;
                                  elsif(srStatus(15)='1') then
                                    srStatus(15)      <= '0';
                                    sdRFM12Binstruction     <= x"B000";
                                    scRFM12Bwe              <= '1';
                                    srReceivedCounter <= srReceivedCounter + 1;
                                    srCurrentState    <= st_read_data;

                                  else
                                    srStatusNew     <= '0';
                                    scINTenable     <= '1';

                                    srCurrentState  <= st_idle;
                                  end if;

                                  -- power management
                                  if (icPowerMode="10" ) then
                                    sdRFM12Binstruction   <= c_RFM12B_SLEEP;
                                    scRFM12Bwe            <= '1';
                                    srNextState     <= st_sleep;
                                    srCurrentState  <= st_wait;
                                  end if;


                                end if;

          when st_clear_fifo  =>
                                  srCurrentState  <= st_clear_fifo;
                                  if (scRFM12Bready = '1') then
                                    sdRFM12Binstruction  <= c_RFM12B_CLEAR_FIFO;
                                    scRFM12Bwe           <= '1';
                                    srCurrentState <= st_accept_data;
                                  end if;

          when st_accept_data  =>
                                  srCurrentState  <= st_accept_data;
                                  if (scRFM12Bready = '1') then
                                    sdRFM12Binstruction  <= c_RFM12B_ENABLE_FIFO;
                                    scRFM12Bwe           <= '1';

                                    srNextState    <= st_idle;
                                    srCurrentState <= st_wait;
                                  end if;

          when st_read_data   =>
                                srCurrentState    <= st_read_data;

                                if (scRFM12BdataValid = '1') then
                                  odData          <= sdRFM12Bdata(15 downto 8);
                                  ocValid         <= '1';

                                  srCurrentState  <= st_idle;
                                end if;

          when st_read_status =>
                                srCurrentState    <= st_read_status;

                                if (scRFM12BdataValid = '1') then
                                  srStatus        <= sdRFM12Bdata;
                                  srStatusNew     <= '1';

                                  srCurrentState  <= srNextState;
                                end if;

         when st_wait       =>
                                srCurrentState  <= st_wait;
                                if (scRFM12Bready = '1') then
                                  srCurrentState <= srNextState;
                                end if;
         when st_transmit_on=>
                                sdRFM12Binstruction <= c_RFM12B_TRANS_ON;
                                scRFM12Bwe          <= '1';

                                srNextState         <= st_transmit_wait;
                                srCurrentState      <= st_wait;
         when st_transmit_wait   =>
                                srCurrentState        <= st_transmit_wait;

                                if (srINT = '1') then
                                  sdRFM12Binstruction     <= x"0000";
                                  scRFM12Bwe              <= '1';
                                  scINTenable       <= '0';
                                  srNextState       <= st_transmit_wait;
                                  srCurrentState    <= st_read_status;
                                end if;

                                if (srStatusNew ='1') then
                                  srStatusNew           <= '0';

                                  if (srStatus(15)='1') then
                                    srStatus(15)        <= '0';
                                    srStatus            <= (others => '0');
                                    scINTenable         <= '1';

                                    sdRFM12Binstruction <= x"B8" & srTransmitBuf;
                                    scRFM12Bwe          <= '1';

                                    srNextState         <= st_transmit;
                                    srCurrentState      <= st_wait;
                                  else
                                    odData              <= srStatus(15 downto 8);
                                    ocValid             <= '1';
                                    scINTenable         <= '1';
                                  end if;
                                end if;

         when st_transmit =>
                                srCurrentState      <= st_transmit;
                                if (srINT='1' and icFrame='1' and icWe='1') then
                                  sdRFM12Binstruction <= x"B8" & idData;
                                  scRFM12Bwe          <= '1';

                                  srNextState         <= st_transmit;
                                  srCurrentState      <= st_wait;
                                elsif(icFrame='0') then
                                  sdRFM12Binstruction <= c_RFM12B_RECV_ON;
                                  scRFM12Bwe          <= '1';
                                  srNextState         <= st_clear_fifo;
                                  srCurrentState      <= st_wait;
                                end if;

         when st_sleep      =>
                              srCurrentState    <= st_sleep;
                              if (icPowerMode="00") then
                                srCounter     <= 0;
                                scINTenable   <= '1';
                                sdRFM12Binstruction <= c_RFM12B_RECV_ON;
                                scRFM12Bwe          <= '1';
                                srNextState   <= st_clear_fifo;
                                srCurrentState<= st_wait;
                              end if;

                              if (icPowerMode="01") then
                                srCounter     <= 0;
                                scINTenable   <= '1';
                                sdRFM12Binstruction <= c_RFM12B_RECV_ON;
                                scRFM12Bwe          <= '1';
                                srNextState   <= st_clear_fifo;
                                srCurrentState<= st_wait;
                              end if;


        end case;


      end if;
    end if;
  end process;




end arch;
