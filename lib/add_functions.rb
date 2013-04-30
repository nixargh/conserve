module Add_functions
	def s_to_a(string) # convert string to array; return array or nil if can't convert
		if string.class == String
			return string.split("\n")
		elsif string.class == Array
			return string
		else
			return nil
		end
	end

	def parse_path(path) # divide path to file on server part and path part etc
		begin
			status = 0
			error = nil
			server = nil
			file = nil
			if path != nil && path != 'module'
				path.gsub!('\\', '/')
				if path.index('|')
					path = path.split('|')
					server = path[0]
					path = path[1]
					file = File.basename(path)
					directory = File.dirname(path)
				else
					file = File.basename(path)
					if File.directory?(path)
						directory = path
						file = nil
					elsif File.directory?(file)
						directory = "#{File.dirname(path)}/#{file}"
					else
						directory = File.dirname(path)
					end
					if 	File.exist?(directory) && File.directory?(directory)
					else
						raise "Can't find directory - #{directory}"
					end
				end
			elsif path != nil && path == 'module'
			else
				raise "path is \"nil\""
			end
		rescue
			status = 1
			error = $!
		end
		result = [status, error, server, directory, file]
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

	def cmd_output(cmd) # get information after running external utility
		begin
			status = 0
			error = nil
			temp_log_err = '/tmp/conseve_cmd_err.log'
			temp_log = '/tmp/conseve_cmd.log'
			`#{cmd} 2>#{temp_log_err} 1>#{temp_log}`
			cmd_error = IO.read(temp_log_err)
			cmd_info = IO.read(temp_log)
		rescue
			status = 1
			error = $!
		ensure
			File.unlink(temp_log_err, temp_log)
		end
		result = [status, error, cmd_info, cmd_error] 
	end

	def runcmd(cmd) # NEW VERSION OF "cmd_output". Get information after running external utility
		begin
			temp_log_err = "/tmp/conseve_cmd_err_#{rand(100)}"
			temp_log = "/tmp/conseve_cmd_#{rand(100)}"
			`#{cmd} 2>#{temp_log_err} 1>#{temp_log}`
			cmd_error = IO.read(temp_log_err)
			cmd_info = IO.read(temp_log)
			cmd_error = nil if cmd_error.length == 0
			cmd_info = nil if cmd_info.length == 0
			return cmd_info, cmd_error
		ensure
			File.unlink(temp_log_err, temp_log)
		end
	end
end
