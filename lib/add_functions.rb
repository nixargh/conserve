#Conserve - linux backup tool.
#Copyright (C) 2013  nixargh <nixargh@gmail.com>
#
#This program is free software: you can redistribute it and/or modify
#it under the terms of the GNU General Public License as published by
#the Free Software Foundation, either version 3 of the License, or
#(at your option) any later version.
#
#This program is distributed in the hope that it will be useful,
#but WITHOUT ANY WARRANTY; without even the implied warranty of
#MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#GNU General Public License for more details.
#
#You should have received a copy of the GNU General Public License
#along with this program.  If not, see http://www.gnu.org/licenses/gpl.html.
module Add_functions
  def s_to_a(string) # convert string to array; return array or nil if can't convert
    if string.class == String
      array = Array.new
      string.each_line{|line|
        array.push(line)
      }
      return array
    elsif string.class == Array
      return string
    else
      return nil
    end
  end

  def format_size(bytes_size) # convert size of file in bytes to some human readable format
    fromated_size = nil
    if bytes_size != nil
      units = ['b', 'Kb', 'Mb', 'Gb', 'Tb']
      index = 0
      size = bytes_size
      until (size / 1024) <= 1
        index += 1
        size = size / 1024
      end
      fromated_size = "#{size.round} #{units[index]}"
    end
    fromated_size
  end

  def runcmd(cmd) # gets information after running external utility
    begin
      temp_log_err = "/tmp/conseve_cmd_err_#{rand(10000)}"
      temp_log = "/tmp/conseve_cmd_#{rand(10000)}"
      temp_exit_code = "/tmp/conseve_exit_code_#{rand(10000)}"
      `#{cmd} 2>#{temp_log_err} 1>#{temp_log}; echo $? > #{temp_exit_code}`
      cmd_error = IO.read(temp_log_err)
      cmd_info = IO.read(temp_log)
      exit_code = IO.read(temp_exit_code)
      cmd_error.chomp!
      cmd_info.chomp!
      exit_code.chomp!
      cmd_error = nil if cmd_error.empty?
      cmd_info = nil if cmd_info.empty?
      if exit_code.empty?
        exit_code = nil
      else
        exit_code = exit_code.to_i
      end
      return cmd_info, cmd_error, exit_code
    rescue
      raise "runcmd: #{$!}"
    ensure
      File.unlink(temp_log_err, temp_log, temp_exit_code)
    end
  end

  def convert_to_non_mapper(device) # convert "device mapper path" to "normal device name"
    temp_symbol = '?'
    device.gsub!(/-{2}/, temp_symbol)
    lg, lv = File.basename(device).split('-')
    device = "/dev/#{lg}/#{lv}"
    device.gsub!(temp_symbol, '-')
    if File.blockdev?(device)
      return device
    else
      raise "Can't convert #{device} to non_mapper"
    end
  end

  def hostname
    `hostname -f`.chomp.strip
  end

end
