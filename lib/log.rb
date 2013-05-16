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
class Log
	attr_accessor :start_time
	
	def initialize()
		@log_file = nil
		@log_enabled = false
		@start_time = nil # don't remember why i need it, hope to findout later
		@skip_time = false
	end

	def enable # start log to file instead of stdout
		@log_enabled = true
	end

	def file # get log file
		@log_file
	end

	def file=(log_file) # set log file
		@log_file = log_file
	end

	def write(info=nil, color=nil, interactive=false) # writing colored text to output WITH "end of line"
		colored_info = to_paint(info, color)
		if @log_enabled == true
			to_log(colored_info, "\n")
			to_stdout(colored_info, "\n") if interactive
		else
			to_stdout(colored_info, "\n")
		end
	end
	
	def write_noel(info=nil, color=nil, interactive=false) # writing colored text to output WITHOUT "end of line"
		colored_info = to_paint(info, color)
		if @log_enabled == true
			to_log(colored_info, '')
			to_stdout(colored_info, '') if interactive
			@skip_time = true
		else
			to_stdout(colored_info, '')
			$stdout.flush
		end
	end

	private

	def to_stdout(info, el) # printing to stdout with or without "end of line" character
		print "#{info}#{el}"
	end
	
	def to_log(info, el) # printing to file with or without "end of line" character
		begin
			File.open(@log_file, "a"){ |openfile|
					@start_time = Time.now.asctime
					if @skip_time == true
						openfile.print "#{info}#{el}"
						@skip_time = false
					else
						openfile.print "#{@start_time} - #{info}#{el}"
					end
				}
			status = 0
			error = nil
		rescue
			status = 1
			error = $!
		end
		result = [status, error]
	end

	def to_paint(info, color) # painting text if color defined
		colored_info = case color
			when nil then info
			when 'red' then red(info)
			when 'yellow' then yellow(info)
			when 'green' then green(info)
			when 'sky_blue' then sky_blue(info)
		end
	end
	
	def colorize(text, color_code) # add color code to start of string and static "end of color" to the end of string
	  "#{color_code}#{text}\e[0m"
	end

	# number of color with they codes
	def red(text); colorize(text, "\e[31m"); end
	def green(text); colorize(text, "\e[32m"); end
	def yellow(text); colorize(text, "\e[33m"); end
	def sky_blue(text); colorize(text, "\e[36m"); end
end
