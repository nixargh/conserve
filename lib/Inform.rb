class Inform
	attr_accessor :config_file

	def initialize
		@config_file = config_file #config file
		@config = nil # configuration hash
		@log = $log
		@log.write("\t#{yellow("Inform function was activated.")}")
		ruby_gems = Ruby_gems.new
		if ruby_gems.check_rubygems == false
			text = "#{red("\t\t\"ruby gem\" utility not installed. Inform function require it.")}"
			@log.write(text)
			puts text
			ruby_gems.install_rubygems
		end
		if ruby_gems.gem_installed?('mail') == false
			text = "#{red("\t\t\"mail\" ruby gem not installed. Inform function require it.")}"
			@log.write(text)
			puts text
			ruby_gems.install_mail_gem
		end
		if ruby_gems.check_rubygems
			require 'rubygems'
			if  ruby_gems.gem_installed?('mail')
				require 'mail'
			else
				raise "\"mail\" ruby gem not installed"
			end
		else
			raise "\"ruby gem\" utility not installed"
		end
	end

	def run
		read_config
		if @config['when_inform'] == 'all'
			report = true
		elsif @config['when_inform'] == 'fail' && $global_error
			report = true
		elsif @config['when_inform'] == 'success' && $global_error == nil
			report = true
		else
			report = false
		end
		if report
			@log.write("\t\t#{yellow("Creating report:")} method \"#{@config['method']}\".")
			if @config['method'] == 'email'
				send_mail
			end
		else
			@log.write("\t\t#{yellow("Nothing to report:")} report case \"#{@config['when_inform']}\" selected.")
		end
	end
		
###########
	private
###########
	def color_schema(item)
		@config['colors'] = 'console' if !@config['colors']
		if @config['colors'] == 'console'
			colors = {
				'background' => 'black',
				'log_text' => 'gray',
				'main_text' => 'white',
				'h_red' => 'red',
				'h_green' => 'green',
				'h_yellow' => 'yellow',
				'h_sky_blue' => 'sky_blue'
			}
		elsif @config['colors'] == 'white'
			colors = {
				'background' => 'white',
				'log_text' => 'black',
				'main_text' => 'blue',
				'h_red' => 'red',
				'h_green' => 'green',
				'h_yellow' => 'orange',
				'h_sky_blue' => 'sky_blue'
			}
		end
		colors[item]
	end

	def log_to_html(info)
		red = "\e[31m"
		green = "\e[32m"
		yellow = "\e[33m"
		sky_blue = "\e[36m"
		teg_close = "\e[0m"

		h_red = "<font color=\"#{color_schema('h_red')}\">"
		h_green = "<font color=\"#{color_schema('h_green')}\">"
		h_yellow = "<font color=\"#{color_schema('h_yellow')}\">"
		h_sky_blue = "<font color=\"#{color_schema('h_sky_blue')}\">"
		h_teg_close = '</font>'
		
		html_info = Array.new
		info = s_to_a(info)
		info.each{|line|
			line.gsub!(red, h_red)
			line.gsub!(green, h_green)
			line.gsub!(yellow, h_yellow)
			line.gsub!(sky_blue, h_sky_blue)
			line.gsub!(teg_close, h_teg_close)
			html_info.push("#{line}<br>")
		}
		html_info
	end
	
	def create_body(info)
		body = Array.new
		last_backup = compact_log(info, 'last')
		if $global_error
			text = 'Backup Job Failed.'
			color = 'red'
		else
			text = 'Backup Job Successfully Completed.'
			color = 'green'
		end
		body.push("<html><body bgcolor=\"#{color_schema('background')}\" text=\"#{color_schema('log_text')}\">\n<pre>\n")
		body.push("<font size=\"12\" color=\"#{color}\" face=\"Arial\">#{text}</font>")
		body.push("<br><font color=\"#{color_schema('main_text')}\"><pre>conserve v.#{$version} #{form_arguments_list($argv)}</pre></font><br>")
		body.push(log_to_html(last_backup))
		body.push("\n</pre>\n</body></html>")
		body
	end
	
	def create_attach(info)
		log_html = log_to_html(info)
		attach = Array.new
		attach.push("<html><body bgcolor=\"black\" text=\"gray\">\n<pre>\n")
		attach.push(log_html)
		attach.push("\n</pre>\n</body></html>")
	end

	def form_arguments_list(arguments)
		arg_string = String.new
		arg_string << "\n"
		arguments.each{|arg|
			arg_string << "\t#{arg}\n"
		}
		arg_string
	end
	
	def create_subject
		hostname = get_hostname
		if $global_error
			"#{hostname}: Conserve Backup Job \"#{$job_name}\" Failed."
		else
			"#{hostname}: Conserve Backup Job \"#{$job_name}\" Success."
		end
	end
	
	def compact_log(info, num_of_lines) # can compact by number of lines from the end or get the last backup info
		info = s_to_a(info)
		info_length = info.length
		if num_of_lines == 'last'
			first_line = info.rindex{|line|
				/ - Backup started - / =~ line
			}
			info_tail = info[first_line..info_length-1]
		else
			info_tail = info[(info_length - num_of_lines)..info_length-1]
		end
	end
	
	def check_potential_log_size(info)
		begin
			tmp_file = '/tmp/canserve.log.html'
			File.open(tmp_file, 'w'){|file|
				file.puts(info)
			}
			File.size?(tmp_file)
		rescue
			raise "Can't check potential conserve log size: #{$!}"
		ensure
			File.unlink(tmp_file)
		end
	end
	
	def send_mail
		error = false
		begin
			config = @config
			options = { 
					:address              => config['smtp_server'],
					:port                 => 25,
					:domain               => get_hostname
				}
		
			if config['auth'] == 'y'
				options.update(
					:authentication       => 'login',
					:user_name            => config['auth_user'],
					:password             => config['auth_pass']
				)
				
			end
		
			if config['tls'] == 'y'
				options.update(
					:enable_starttls_auto => true
				)
			elsif config['tls'] == 'n'
				options.update(
					:enable_starttls_auto => false
				)
			end
			
			Mail.defaults do
				delivery_method :smtp, options
			end
			
			if @log.log_file
				log = File.read(@log.log_file)
			else
				raise "Can't read log file, because it's not specified."
			end

			if check_potential_log_size(log) >= 2097152
				rest_lines = 300
				@log.write("\t\tHTML log size more than 2 Mb, compacting to #{yellow(rest_lines)} lines from the end.")
				log = compact_log(log, rest_lines)
			end
		
			body_html = create_body(log)
			attach_html = create_attach(log)
			diff_subject = create_subject
			
			if config['attach_log'] == 'y'
				mail = Mail.new do
					from     config['mail_from']
					to       config['mail_to']
					subject  diff_subject
					html_part do
						content_type 'text/html; charset=UTF-8'
						body body_html
					end
					add_file :filename => 'conserve.log.html', :content => attach_html
				end
			else	
				mail = Mail.new do
					from     config['mail_from']
					to       config['mail_to']
					cc		 config['copy_to']
					subject  diff_subject
					html_part do
						content_type 'text/html; charset=UTF-8'
						body body_html
					end
				end
			end
			mail.deliver!
		rescue Net::SMTPFatalError
			error = $!
		rescue Net::SMTPAuthenticationError
			error = $!
		rescue SocketError
			error = $!
		rescue EOFError
			error = "Email sending failed: #{$!}. Maybe you forgot to set up Anonymous Receive Connector or a wrong credentials were set."
		rescue RuntimeError
			error = $!
		rescue OpenSSL::SSL::SSLError
			error = "SSL connection to mail server failed: #{$!}."
		rescue => detail
			@log.write(detail.class)
			@log.write(detail.backtrace.join("\n"))
			error = $!
		end
		@log.write("\t#{red("Inform Error:")} #{yellow(error)}") if error
	end
	
	def get_hostname
		hostname = `hostname`
		hostname.chomp!
	end

	def read_config
		create_config if File.exist?(@config_file) == false
		@log.write_noel("\t\tReading Inform configuration - ")
		if @config == nil
			@config = Hash.new
			IO.read(@config_file).each_line{|line|
				line = line.chomp.split('=', 2)
				@config[line[0]] = line[1]
			}
		end
		if @config
		 	@log.write("[ #{green('OK')} ]")
		else
			@log.write("[ #{red('FAILED')} ]")
			raise "Can't read and create Inform config: #{$!}"
		end
	end
	
	def create_config
		@log.write("#{yellow("\t\t#{@config_file} file not found. Let's create it:")}")
		conf_info = Hash.new
		begin
			print sky_blue("\t\t\tAbout which events to inform? [fail|success|all]: ")
			when_inform = $stdin.gets.chomp
		end while when_inform != 'fail' && when_inform != 'success' && when_inform != 'all'
		conf_info['when_inform'] = when_inform
		puts "#{sky_blue("\t\t\tSelect inform method [email]: ")} email"
		conf_info['method'] = 'email'
		begin
			print sky_blue("\t\t\tSelect color schema for report? [console|white]: ")
			conf_info['colors'] = $stdin.gets.chomp
		end while conf_info['colors'] != 'console' && conf_info['colors'] != 'white'
		begin
			print sky_blue("\t\t\tAttach log file to report? [y|n]: ")
			conf_info['attach_log'] = $stdin.gets.chomp
		end while conf_info['attach_log'] != 'y' && conf_info['attach_log'] != 'n'
		begin
			print sky_blue("\t\t\tUse TLS to connect to server? [y|n]: ")
			conf_info['tls'] = $stdin.gets.chomp
		end while conf_info['tls'] != 'y' && conf_info['tls'] != 'n'
		if conf_info['method'] == 'email'
			print sky_blue("\t\t\tSMTP server?: ")
			conf_info['smtp_server'] = $stdin.gets.chomp
			begin
				print sky_blue("\t\t\tAuthenticate before send? [y|n]: ")
				auth = $stdin.gets.chomp
			end while auth != 'y' && auth != 'n'
			conf_info['auth'] = auth
			if conf_info['auth'] == 'y'
				print sky_blue("\t\t\tUsername: ")
				conf_info['smtp_user'] = $stdin.gets.chomp
				print sky_blue("\t\t\tPassword: ")
				system "stty -echo"
				conf_info['smtp_pass'] = $stdin.gets.chomp
				system "stty echo"
			end
			print sky_blue("\t\t\tSend mail to: ")
			conf_info['mail_to'] = $stdin.gets.chomp
			print sky_blue("\t\t\tSend copy to: ")
			conf_info['copy_to'] = $stdin.gets.chomp
			print sky_blue("\t\t\tSend mail from: ")
			conf_info['mail_from'] = $stdin.gets.chomp
		end
		if File.directory?(File.dirname(@config_file))
			File.open(@config_file, "w"){ |openfile|
				conf_info.each{|option, value|
					openfile.puts "#{option}=#{value}"
				}
			}
		else
			raise "Can't access #{File.dirname(@config_file)} directory"
		end
		@config = conf_info
	end
end
