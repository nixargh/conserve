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
class Ruby_gems
	attr_accessor :log
	include Add_functions

	def initialize
		@rubygems_tarball_url = 'http://files.rubyforge.vm.bytemark.co.uk/rubygems/rubygems-1.8.25.tgz'
	end
	
	def install_rubygems
		answer = nil
		while answer != 'y' && answer != 'n' do
			@log.write_noel("\t\t\t\tWould you like to install \"ruby gem\" utility? [y|n]: ", 'sky_blue', true)
			answer = $stdin.gets.chomp
		end
		if answer == 'n'
			raise "Inform aborded"
		else
			begin
				os = detect_os[0]
				if os == 'Ubuntu'
					`apt-get update`
					`apt-get -y install rubygems`
				elsif os == 'CentOS'
					`yum -y install rubygems`
				else
					while answer != 'y' && answer != 'n' do
						@log.write_noel("\t\t\t\t\tDownload and install it from #{@rubygems_tarball_url}? [y|n]: ", 'sky_blue', true)
						answer = $stdin.gets.chomp
					end
					if answer == 'n'
						raise "Inform aborded"
					else
						download_dir = "/tmp/ruby_rpms_temp"
						Dir.mkdir(download_dir)
						rubygems_tarball = get_rubygems(download_dir)
						install_rubygems_tarball(rubygems_tarball)
					end
				end
			ensure
				if download_dir
					info, error, exit_code = runcmd("rm -fr #{download_dir}")
					if exit_code != 0
						@log.write("\t\t\t\t\t\tCan't delete #{download_dir}: #{$!}", 'yellow')
					end
				end
			end
		end
	end
	
	def check_rubygems
		gem = `which gem 2>/dev/null`.chomp
		gem == '' ? false : gem
	end
	
	def gem_installed?(gem)
		gem_cmd = check_rubygems
		if gem_cmd
			`#{gem_cmd} list #{gem}`.index('mail') ? true : false
		end
	end
	
	def install_mail_gem
		answer = nil
		while answer != 'y' && answer != 'n' do
			@log.write_noel("\t\t\t\tWould you like to install \"mail\" ruby gem? [y|n]: ", 'sky_blue', true)
			answer = $stdin.gets.chomp
		end
		if answer == 'n'
			raise "Inform aborded"
		else
			install_gem('mail')
		end
	end

###########
#	private
###########
	
	def detect_os
		rel_file = nil
		Dir.entries('/etc').each{|file|
			rel_file = file if /-release/ =~ file
		}
		rel_info = IO.read("/etc/#{rel_file}")
		rel_info = s_to_a(rel_info)
		if rel_info[0].index('SUSE Linux Enterprise Server 11')
			os = 'SLES11'
			arch = nil
		elsif rel_info[0] == 'DISTRIB_ID=Ubuntu'
			os = 'Ubuntu'
			arch = nil
		elsif rel_info[0].index('CentOS')
			os = 'CentOS'
			arch = nil
		end
		result = [os, arch]
	end
	
	def install_gem(gem)
		gem_cmd = check_rubygems
		if gem_cmd
			@log.write("\t\t\t\t\tInstalling ruby gem \"#{gem}\"...")
			`#{gem_cmd} install #{gem}`
		else
			raise "Failed to find \"ruby gem\" utility"
		end
	end
	
	def	get_rubygems(where)
		begin
			@log.write_noel("\t\t\t\t\tDownloading rubygems tarball from #{@rubygems_tarball_url} - ")
			require 'net/http'
			proto, trash, host, link = @rubygems_tarball_url.split('/', 4)
			destination = "#{where}/rubygems.tgz"
			Net::HTTP.start(host){ |http|
				resp = http.get("/#{link}")
				File.open(destination, 'wb'){ |file|
					file.write(resp.body)
				}
			}
			raise "File #{destination} not found" if !File.exist?(destination)
			@log.write('[OK]', 'green')
			destination
		rescue
			@log.write('[FAILED]', 'red')
			raise "Can't download rubygems tarball: #{$!}."
		end
	end
	
	def install_rubygems_tarball(tarball)
		begin
			@log.write_noel("\t\t\t\t\tInstalling rubygems from tarball \"#{tarball}\" - ")
			extract_dir = File.dirname(tarball)
			info, error, exit_code = runcmd("tar -xzf #{tarball} -C #{extract_dir}")
			raise "Can't extract rubygems tarball: #{error}" if exit_code != 0
			require 'find'
			Find.find(extract_dir){ |path|
				if File.basename(path) == 'setup.rb'
					info, error, exit_code = runcmd("ruby #{path}")
					if exit_code == 0
						@log.write('[OK]', 'green')
						return true
					else
						raise "setup.rb failed: #{$!}"
					end
				end
			}
			raise "Can't find setup.rb"
		rescue
			@log.write('[FAILED]', 'red')
			raise "Can't install rubygems from tarball: #{$!}."
		end
	end
end
