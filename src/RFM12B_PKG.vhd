-------------------------------------------------------
--! @file
--! @brief Package file with function definitions for RFM12B
--! @author Dominik Meyer
--! @email dmeyer@hsu-hh.de
--! @date 2017-01-26
--! @copyright 2017 by Dominik Meyer (License GPLv2)
-------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;
use ieee.numeric_std.all;

--! Package file with function definitions for RFM12B

--! the RFM12B datasheet provides some functions to calculate required instrcution parameters
package RFM12B_pkg  is


  function f_RFM12_BASEBAND(band : integer) return std_logic_vector;                      --! return the bits for selecting the correct baseband frequency(433, 868, 915)
  function f_RFM12_TXCONF_FS_CALC(f : integer ) return std_logic_vector;                  --! calculate the TX frequency
  function f_RFM12_FREQUENCY_CALC(band : integer; f : integer) return std_logic_vector;   --! calculate the frequency parameter according to the baseband and the wanted frequency
  function f_RFM12_DATARATE_CALC(d : integer ) return std_logic_vector;                   --! calculate the datarate parameter according to the provided datarate

end RFM12B_pkg;

--! body of the RFM12B package
package body RFM12B_pkg is

  --! f_RFM12_BASEBAND
  --! return the parameter bits for selecting the correct baseband frequency
  --!
  --! @param band the baseband to use, available values are 433, 868, 915
  --! @return two bit vector, parameter for the configuration instruction
  function f_RFM12_BASEBAND(band : integer) return std_logic_vector is
  begin
    case band is
      when 433    =>  return "01";
      when 868    =>  return "10";
      when 915    =>  return "11";
      when others =>  return "01";
    end case;
  end f_RFM12_BASEBAND;


  --! f_RFM12_FREQUENCY_CALC
  --! calculate the frequency paramter for the frequency configuration command
  --!
  --! @param band the baseband to use, available values are 433, 868, 915
  --! @frequency the frequency in Hz
  --! @return 12 bit vector, paramter for the frequency configuration command
  function f_RFM12_FREQUENCY_CALC(band : integer; f : integer) return std_logic_vector is
    variable ret : integer := 0;
  begin
    case band is
      when 433    =>  ret := (f-430000000)/2500;
      when 868    =>  ret := (f-860000000)/5000;
      when 915    =>  ret := (f-910000000)/7500;
      when others =>  ret := 0;
    end case;

    return std_logic_vector(to_unsigned(ret,12));
  end f_RFM12_FREQUENCY_CALC;

  --! f_RFM12_DATARATE_CALC
  --! calculate the datarate paramter for the receiver configuration command
  --!
  --! @param d datarate to use in baud
  --! @return 7 bit vector, parameter to the receiver configuration command
  function f_RFM12_DATARATE_CALC(d : integer) return std_logic_vector is
    variable ret : integer := 0;
    variable cs  : std_logic := '0';
  begin
    if (d >= 2700) then
      ret := (((100000000 / 290 / d*10 ) - 5) / 10)+1;
      cs  := '0';
    else
      ret := ((10000000 / 29 / 8 / d )*10 - 5) / 10;
      cs  := '1';
    end if;
    return cs & std_logic_vector(to_unsigned(ret,7));
  end f_RFM12_DATARATE_CALC;

  --! f_RFM12_TXCONF_FS_CALC
  --! calculate the FS value for the transmitter configuration
  --!
  --! @param f the frequency in Hz
  --! @return 4 bit vector
  function f_RFM12_TXCONF_FS_CALC(f : integer) return std_logic_vector is
    variable ret : integer := 0;
  begin
    ret   := (f / 15000)-1;
    return std_logic_vector(to_unsigned(ret,4));

  end f_RFM12_TXCONF_FS_CALC;
end RFM12B_pkg;
