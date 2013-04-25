class Add_functions
	def s_to_a(string)
		if string.class == String
			return string.split("\n")
		elsif string.class == Array
			return string
		else
			return nil
		end
	end

	def parse_path(path)
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

	def format_size(bytes_size)
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
end
