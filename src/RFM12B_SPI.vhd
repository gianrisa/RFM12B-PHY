-------------------------------------------------------
--! @file
--! @brief SPI Component for communicating with the RFM12B wireless chip
--! @author Dominik Meyer
--! @email dmeyer@hsu-hh.de
--! @date 2017-01-25
--! @copyright 2017 by Dominik Meyer (License GPLv2)
-------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;

--! SPI Component for communicating with the RFM12B wireless chip

--! The RFM12B Chips requires command words of 16bit length.
--! Sometimes it is recommended to transmit the first 8 bits, have
--! a very small pause without SCK but SELn=0
--! This componend implements this behaviour.
--!
--! The RFM12B has one command which requires a 16 bit command word
--! and an additional 8 bit command for shifting out the results.
--! The command is the x"B000", the FIFO read command.
--! This component implements the additional 8 bit shift for just
--! this command.
entity RFM12B_SPI is
  generic(
    GEN_SysClockinHz      : integer := 200000000;                 --! the System Clock feeded into iClk in Hz
    GEN_SPI_ClockinHz     : integer :=   2000000                  --! the SPI Clock to use. The RFM12B supports up to 2.5MHz in FIFO mode,
                                                                  --! using very small values is not recommended because of FIFO overflows
  );
  port (
    -- User Interface
    ocReady         : out std_logic;                              --! Signals that the component is ready to transmit the next instruction
    idInstruction   :  in std_logic_vector(15 downto 0);          --! the instruction to be transmitted to the RFM12B
    icWe            :  in std_logic;                              --! indicates that idInstruction should be transmitted

    odData          : out std_logic_vector(15 downto 0);          --! the data shifted out of the RFM12B, in case of the x"B000" instruction bits 15 downto 8 are the read byte
    ocValid         : out std_logic;                              --! odData is valid
    ocINT           : out std_logic;                              --! active high reset line indicating an interrupt in the RFM12B
    icReset         :  in std_logic;                              --! active high reset of the RFM12B, has to be high at least 5ms

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
end RFM12B_SPI;

architecture arch of RFM12B_SPI is

  component clkEnable
    generic (
      GEN_FreqIn_Hz  : integer := 200000000;
      GEN_FreqOut_Hz : integer := 100000000
    );
    port (
      iClkin  : in  STD_LOGIC;
      iReset  : in  STD_LOGIC;
      oeClkEn : out STD_LOGIC         --! signal description output clockEnable
    );
  end component clkEnable;

  component spiMaster
    generic (
      Gen_DataLength : integer := 8
    );
    port (
      iSysClk       : in  std_logic;
      iSPIclkEn     : in  std_logic;
      iReset        : in  std_logic;
      odMOSI        : out std_logic;
      idMISO        : in  std_logic;
      oSClk         : out std_logic;
      icCPOL        : in  std_logic;
      icCPHA        : in  std_logic;
      odByteRead    : out std_logic_vector (Gen_DataLength - 1 downto 0);
      idByteWrite   : in  std_logic_vector (Gen_DataLength - 1 downto 0);
      icStart      : in  std_logic;
      ocReadyToSend : out std_logic                       --! spi host is ready for a transfer - handshake signal
    );
  end component spiMaster;


  signal scSPIclockEn   : std_logic;
  signal sdByteRead     : std_logic_vector(7 downto 0);
  signal sdByteWrite    : std_logic_vector(7 downto 0);
  signal scStart        : std_logic;
  signal scReadyToSend  : std_logic;


  signal srCounter          : integer := 0;

  signal srDataIN           : std_logic_vector(15 downto 0);
  signal srDataTemp         : std_logic_vector(7 downto 0);
  signal srDataWrite        : std_logic_vector(15 downto 0);
  signal srRead             : std_logic;
  --
  -- FSM
  --
  type t_states is (st_start, st_idle, st_write0, st_write1, st_wait0, st_wait1, st_valid);
  signal srCurrentState : t_states;
  signal srNextState    : t_states;

begin

  ocINT   <= not icINTn;
  odData  <= srDataIN;
  ocResetN<= not icReset;


  --! clock enable component to generate the correct SPI clock rate
  clkEnable_i : clkEnable
  generic map (
    GEN_FreqIn_Hz  => GEN_SysClockinHz,
    GEN_FreqOut_Hz => 2000000
  )
  port map (
    iClkin  => iClk,
    iReset  => iReset,
    oeClkEn => scSPIclockEn
  );

  --! SPI master comoponent doing the SPI communication
  spiMaster_i : spiMaster
      generic map (
        Gen_DataLength => 8
      )
      port map (
        iSysClk       => iClk,
        iSPIclkEn     => scSPIclockEn,
        iReset        => iReset,
        odMOSI        => odSDI,
        idMISO        => idSDO,
        oSClk         => oSClk,
        icCPOL        => '0',
        icCPHA        => '0',
        odByteRead    => sdByteRead,
        idByteWrite   => sdByteWrite,
        icStart       => scStart,
        ocReadyToSend => scReadyToSend
      );

  --! generate the ocReady signal asynchronous for faster reaction time
  ocReady             <= '1' when srCurrentState=st_start and scReadyToSend='1' else
                         '1' when srCurrentState=st_idle and icWe='0' else
                         '0';

  --! FSM to control the communication process to the RFM12B
  fsm: process(iClk)
  begin
    if (rising_edge(iClk)) then
      if (iReset = '1') then
        ocSELn          <= '1';
        scStart         <= '0';
        sdByteWrite     <= (others => '0');
        srCounter       <= 0;
        ocValid         <= '0';
        srDataTemp      <= (others => '0');
        srDataIN        <= (others => '0');
        srRead          <= '0';

        srNextState     <= st_idle;
        srCurrentState  <= st_start;

      elsif(iClkEn = '1') then
        ocSELn          <= '1';
        scStart         <= '0';
        ocValid         <= '0';

        case srCurrentState is


          when st_start       =>
                                if (scReadyToSend = '1') then
                                    srCounter       <= 0;
                                    ocSELn          <= '1';
                                    srRead          <= '0';
                                    srCurrentState  <= st_idle;
                                 end if;

          when st_idle        =>
                                  srCurrentState  <= st_idle;
                                  srRead          <= '0';

                                  if (icWe = '1') then

                                      srDataWrite     <= idInstruction;
                                      srCurrentState  <= st_write0;

                                      if (idInstruction(15 downto 8) = x"B0") then  -- read from fifo
                                        srRead        <= '1';
                                      end if;
                                  end if;

          when st_write0       =>
                                  sdByteWrite     <= srDataWrite(15 downto 8);
                                  ocSELn          <= '0';
                                  scStart         <= '1';

                                  srNextState     <= st_write1;
                                  srCurrentState  <= st_wait0;
          when st_write1       =>
                                  sdByteWrite     <= srDataWrite( 7 downto 0);
                                  scStart         <= '1';
                                  ocSELn          <= '0';

                                  srDataIN(15 downto 8) <= srDataTemp;

                                  srNextState     <= st_valid;
                                  srCurrentState  <= st_wait0;

                                  -- if we have a fifo read request we have to write/read one byte more
                                  if (srRead = '1') then
                                    srRead        <= '0';
                                    srDataWrite   <= (others => '0');
                                    srDataTemp    <= (others => '0');
                                    srNextState   <= st_write1;
                                    srCurrentState<= st_wait0;
                                  end if;


          when st_wait0        =>
                                  srCurrentState    <= st_wait0;
                                  ocSELn            <= '0';
                                  scStart           <= '1';

                                  if (scReadyToSend = '0') then
                                    scStart         <= '0';
                                    srCurrentState  <= st_wait1;
                                  end if;


          when st_wait1        =>
                                  srCurrentState    <= st_wait1;
                                  ocSELn          <= '0';

                                  if (scReadyToSend = '1') then
                                    srDataTemp      <= sdByteRead;

                                    srCurrentState  <= srNextState;
                                  end if;

        when st_valid          =>
                                  srCurrentState      <= st_idle;
                                  srDataIN(7 downto 0)<= srDataTemp;
                                  ocValid             <= '1';
                                  srRead              <= '0';

        end case;

      end if;
    end if;
  end process;


end arch;
