if RUBY_DESCRIPTION[0...10] != 'ruby 1.9.3'
	puts "This task has to be run with ruby 1.9.3 (found #{RUBY_DESCRIPTION}). Install rvm and ruby 1.9.3"
	exit 0
end

require 'optparse'
require 'fileutils'
require 'date'
require 'tmpdir'
require 'thread'

options = {}

optparse = OptionParser.new do |opts|
   # Set a banner, displayed at the top
   # of the help screen.
   opts.banner = "Usage: condense_png.rb --source <sourcefolder> --reduction-percentage <Reduction % watermark> --min-file-size <Minimum file size before reduction> --depth <Folder depth to look for PNGs>"

   options[:verbose] = false
   opts.on( '-v', '--verbose', "Show output of the current task" ) do
     options[:verbose] = true
   end
 
   options[:source] = nil
   opts.on( '-s', '--source FOLDER', 'Specify the source folder to look for PNGs' ) do |folder|
        if Dir.exists?(folder)
            options[:source] = folder
        else
            puts "Could not find #{folder}"
            exit 1
        end
   end
   
   options[:depth] = 1
   opts.on( '-d', '--depth NUM', Integer, 'The folder depth to look for PNGs, default:1' ) do |depth|
        options[:depth] = depth
   end
   
   options[:reduction_percentage] = 5
   opts.on( '-rp', '--reduction-percentage NUM', Integer, 'Reduction % watermark, default: 5' ) do |percentage|
        unless percentage > 0 && percentage < 95
            puts "Please specify a meaningful value for the reduction % watermark, #{ARGV[1]} doesn't make any sense."
            exit 1
        else
            options[:reduction_percentage] = percentage
        end
   end

   options[:min_file_size] = "10k"
   opts.on( '-min', '--min-file-size SIZEk', 'Minimum file size before reduction, default: 10k' ) do |min_file_size|
        options[:min_file_size] = min_file_size
   end
   
 
   # This displays the help screen, all programs are
   # assumed to have this option.
   opts.on( '-h', '--help', 'Display this screen' ) do
     puts opts
     exit
   end
end

optparse.parse!

SOURCE_DIR = options[:source]
REDUCTION_PERCENTAGE_WATERMARK = options[:reduction_percentage]
REDUCTION_MIN_SIZE = options[:min_file_size]
DEPTH = options[:depth]
VERBOSE     = options[:verbose]

# Required commandline tools
IM_CONVERT  = "/usr/local/bin/convert"
IM_IDENTIFY = "/usr/local/bin/identify"
JPEGOPTIM   = "/usr/local/bin/jpegoptim"

[ IM_CONVERT, IM_IDENTIFY, JPEGOPTIM ].each do |image_tool|
	unless File.exists?(image_tool)
		puts "Could not find '#{image_tool}'. Please install (likely with brew)!"
		exit 0
	end
end

MAX_CONCURRENT_THREADS = `sysctl -n hw.ncpu`.strip.to_i

def find_parallel(find_command, &block)
	puts "> #{find_command}" if VERBOSE
	
	queue = Queue.new # or bounded queue
	
	def cont(item) !item.nil? end
	
	threads = (1..MAX_CONCURRENT_THREADS).map do
		Thread.new do
			while (cont(item = queue.deq))
				block.call(item)
			end
		end
	end
	
	`#{find_command}`.split("\n").each do |image_file|
		queue.enq image_file
	end
	
	threads.size.times do
		queue.enq nil # terminate
	end
	
	threads.each {|th| th.join}	
end

def optimize_image(image_file)
	extension = File.extname(image_file).downcase
	`#{JPEGOPTIM} --strip-all -q -m90 "#{image_file}"` if extension == ".jpg"
end

puts "Condensing PNGs..." if VERBOSE
overall_reduced_bytes = 0
total_old_file_size = 0
file_count = 0
image_blacklist = [ "Default-Landscape@2x~ipad.png", "Default-Landscape~ipad.png" ]
find_parallel("find \"#{SOURCE_DIR}\" -name \"*.png\" -type f -size +#{REDUCTION_MIN_SIZE} -depth #{DEPTH}") do |image_file|
    next if image_blacklist.include?(File.basename(image_file))
    
    image_base_name = "#{File.dirname(image_file)}/#{File.basename(image_file, File.extname(image_file))}"
    
    `#{IM_CONVERT} -type optimize -strip -quality 100 "#{image_base_name}.png" "#{image_base_name}_color.jpg"`
    optimize_image "#{image_base_name}_color.jpg"
    `#{IM_CONVERT} -alpha Extract -negate -type optimize -strip -quality 100 +dither "#{image_base_name}.png" "#{image_base_name}_alpha.jpg"`
    optimize_image "#{image_base_name}_alpha.jpg"
    new_file_size = File.size?("#{image_base_name}_color.jpg")+File.size?("#{image_base_name}_alpha.jpg")
    old_file_size = File.size?("#{image_base_name}.png")
    total_old_file_size += old_file_size
    reduction_percentage = Integer(100-(Float(new_file_size)/Float(old_file_size))*100)
    if reduction_percentage >= REDUCTION_PERCENTAGE_WATERMARK
        puts "Splitted #{File.basename(image_file)}, reduced size by #{reduction_percentage} %" if VERBOSE
        image_width, image_height = `#{IM_IDENTIFY} -format "%w,%h" "#{image_file}"`.split(",").map { |value| Integer(value) }
        File.delete("#{image_base_name}.png")
        
        data_alpha = File.open("#{image_base_name}_alpha.jpg", "rb")
        data_color = File.open("#{image_base_name}_color.jpg", "rb")
        output_file = File.open("#{image_base_name}.png_condensed", 'wb')
        output_file.write([image_width,image_height,data_alpha.size].pack("vvV"))
        IO::copy_stream(data_alpha, output_file)
        IO::copy_stream(data_color, output_file)
        data_alpha.close
        data_color.close
        output_file.close
        
        overall_reduced_bytes += (old_file_size - new_file_size)
    else
        puts "Undoing split of #{File.basename(image_file)}, new size was #{new_file_size}, old size was not so bad #{old_file_size}, #{reduction_percentage} %" if VERBOSE
    end
    File.delete("#{image_base_name}_color.jpg")
    File.delete("#{image_base_name}_alpha.jpg")
    
    file_count+=1
end

puts if VERBOSE

percentage_reduction = overall_reduced_bytes.to_f / total_old_file_size * 100
if percentage_reduction > 0
    puts "*** Processed #{file_count} files, reduced by #{sprintf('%.1f',percentage_reduction)} % (original size:#{total_old_file_size}, reduced by size:#{overall_reduced_bytes}, new size:#{total_old_file_size-overall_reduced_bytes})"
else
    puts "*** Could not gain any file size reduction."
end