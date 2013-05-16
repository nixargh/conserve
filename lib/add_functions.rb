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

#	def cmd_output(cmd) # get information after running external utility
#		begin
#			status = 0
#			error = nil
#			temp_log_err = '/tmp/conseve_cmd_err.log'
#			temp_log = '/tmp/conseve_cmd.log'
#			`#{cmd} 2>#{temp_log_err} 1>#{temp_log}`
#			cmd_error = IO.read(temp_log_err)
#			cmd_info = IO.read(temp_log)
#		rescue
#			status = 1
#			error = $!
#		ensure
#			File.unlink(temp_log_err, temp_log)
#		end
#		result = [status, error, cmd_info, cmd_error] 
#	end

	def runcmd(cmd) # NEW VERSION OF "cmd_output". Get information after running external utility
		begin
			temp_log_err = "/tmp/conseve_cmd_err_#{rand(10000)}"
			temp_log = "/tmp/conseve_cmd_#{rand(10000)}"
			`#{cmd} 2>#{temp_log_err} 1>#{temp_log}`
			cmd_error = IO.read(temp_log_err)
			cmd_info = IO.read(temp_log)
			cmd_error = nil if cmd_error.length == 0
			cmd_info = nil if cmd_info.length == 0
			return cmd_info, cmd_error
		rescue
			raise "runcmd: #{$!}"
		ensure
			File.unlink(temp_log_err, temp_log)
		end
	end
end
