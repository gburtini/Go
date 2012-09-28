#!/usr/bin/env ruby
require 'optparse'

DEFAULT_NAME = File.expand_path "~/.go.data"
DEFAULT_EDITOR = "vim"

def printVerbose(string) 
	if ($options[:verbose] or $options[:extra_verbose]) then
		$stderr.puts string
	end
end

def printExtraVerbose(string)
	if($options[:extra_verbose]) then
		$stderr.puts string
	end
end

# invokes $EDITOR on the file. if the file doesn't exist, creates it and puts a comment at the top.
def editFile(file)
	if ( ! File.exists?(file)) then
		fh = File.new(file, File::CREAT|File::TRUNC|File::RDWR);
		fh.write("# Put entries below here with [slug | path | title]");
		fh.close
	end

	printVerbose("Starting editor on " + file)
	
	if (ENV.key?("EDITOR"))  then
		system( ENV['EDITOR'] + ' ' + file )
	else
		system( DEFAULT_EDITOR + ' ' + file )
	end
	puts "Database file " + file + " updated.\n"
	Process.exit
end

# prints a list of all the values in the database
def listEntries(file) 
	printVerbose("Listing entries in " + file)
	list = File.open(file).readlines

	printVerbose("Found " + list.count.to_s + " lines.")
	list.each do |entry|
		if !(/^\s*[#%]/.match(entry) || /^$/.match(entry)) then
			values = entry.split(/\|/).map do |value|
				value.strip!
			end
			
			if (values != nil) then
				if (values[3] != nil) then
					values[1] = "ssh " + values[1]
				end
				puts values[0] + " - " + values[2].to_s + " (" + values[1] + ")"
			end
		end
	end
end

# searches the file for the first match in the searches array.
def searchEntries(file, searches)
	printVerbose("Searching the entries in " + file)

        if File.exists?(file)
                list = File.open(file).readlines
        else
		printVerbose("File did not exist. Creating it.")
                editFile(file)
        end

        searches.each do |search|
		printExtraVerbose("Searching for string " + search)
                list.each do |v|
			printExtraVerbose("Checking row " + v)
			# TODO: validate row here.

			mode = :directory
			
                        values = v.split(/\|/).map do |a|
				a.strip!
			end

			if(values.count > 3 and values[3] == "ssh") then
				mode = :ssh
			end

                        if (values[0] == search)
				case mode
					when :directory
						printVerbose("Found " + search + " -- executing.")
		                                puts values[2] + " ==> Changing directory to " + values[1]
                		                Dir.chdir(File.expand_path values[1])	# output the actual path for the bash script to redirect.
						exec 'bash'

					when :ssh
						exec 'bash -c "ssh" ' + values[1]
				end

				Process.exit
                        end
                end
        end
end
	

$options = {}
OptionParser.new do |opts|
	opts.banner = "Usage: go [-l] [-e] [-w] [-v] [-h] [-d db_path] [slug]"
	$options[:verbose] = false;
	$options[:extra_verbose] = false;
	opts.on('-v', '--verbose', "Output more information.") do
		$options[:verbose] = true
	end
	opts.on('-w', '--extra-verbose', "Output even more information.") do
		$options[:extra_verbose] = true
	end
	

	$options[:db_path] = DEFAULT_NAME
	opts.on('-d', '--database-path FILE', 'Specify an alternative database. By default, /var/go.data.') do |val|
		$options[:db_path] = val
	end

	$options[:mode] = :search
	opts.on('-e', '--edit', 'Edit the database.') do 
		$options[:mode] = :edit
	end

	opts.on('-l', '--list', 'List the database.') do 
		$options[:mode] = :list
	end

	opts.on_tail( '-h', '--help', 'Display this screen.' ) do
     		puts opts
   		Process.exit
	end
end.parse!

case $options[:mode]
	when :edit
		editFile($options[:db_path])
	when :list
		listEntries($options[:db_path])
	else	# when :search
		searchEntries($options[:db_path], ARGV)
end

