#!/usr/bin/env ruby

require 'securerandom'
require 'webrick'
require 'openssl'
require 'fileutils'

BASEDIR = '/home/backup/android'
CACHEDIR = "#{BASEDIR}/.esback_cache"

FileUtils.mkdir_p CACHEDIR
256.times do |i|
  hex = '%02x' % i
  FileUtils.mkdir_p("#{CACHEDIR}/#{hex}")
end


@sess_to_dir = {}

def handle_begin(req, res)
  sess = SecureRandom.uuid
  dir = Time.now.localtime.strftime('%Y%m%d-%H%M%S')
  $stderr.puts "#{sess} -> #{dir}"
  @sess_to_dir[sess] = dir
  res.cookies << WEBrick::Cookie.new('session', sess)
end

def handle_file(req, res)
  sess = req.cookies.select{|c| c.name == 'session'}.first.value
  dir = @sess_to_dir[sess]
  unless dir
    res.status = 403
    return
  end
  
  dir = "#{BASEDIR}/#{dir}"
  Dir.mkdir(dir) unless File.exist? dir
  
  filepath = req.path.sub(%r|^/file/|, '').sub(%r|^/*|, '')
  filepath_sha256 = OpenSSL::Digest::SHA256.hexdigest(filepath)
  filepath_div = filepath_sha256.slice(0, 2)
  filepath = "#{dir}/#{filepath}"
  
  body = req.body
  body_sha256 = OpenSSL::Digest::SHA256.hexdigest(body)
  new_cachefile = "#{CACHEDIR}/#{filepath_div}/#{filepath_sha256}-#{body_sha256}"
  
  old_cachefile = Dir.glob("#{CACHEDIR}/*/*-#{body_sha256}").first
  
  unless File.exist? new_cachefile
    if old_cachefile
      File.link old_cachefile, new_cachefile unless old_cachefile == new_cachefile
    else
      File.write new_cachefile, body
    end
  end
  FileUtils.mkdir_p File.dirname(filepath)
  File.link new_cachefile, filepath
  
end

def handle_keep(req, res)
  sess = req.cookies.select{|c| c.name == 'session'}.first.value
  dir = @sess_to_dir[sess]
  unless dir
    res.status = 403
    return
  end
  
  dir = "#{BASEDIR}/#{dir}"
  Dir.mkdir(dir) unless File.exist? dir
  
  if req.body
    req.body.split("\n").each do |filepath|
      filepath = filepath.sub(%r|^/*|, '')
      filepath_sha256 = OpenSSL::Digest::SHA256.hexdigest(filepath)
      filepath_div = filepath_sha256.slice(0, 2)
      filepath = "#{dir}/#{filepath}"
      
      new_cachefile = Dir.glob("#{CACHEDIR}/#{filepath_div}/#{filepath_sha256}-*").first
      if new_cachefile
        FileUtils.mkdir_p File.dirname(filepath)
        File.link new_cachefile, filepath
      end
    end
  end
  
end

def handle_finish(req, res)
  sess = req.cookies.select{|c| c.name == 'session'}.first.value
  dir = @sess_to_dir[sess]
  unless dir
    res.status = 403
    return
  end
  @sess_to_dir[sess] = nil
  
  orig_dir = dir
  new_dir = "#{dir}-daily"
  now = Time.now.localtime
  new_dir = "#{new_dir}-weekly" if now.monday?
  new_dir = "#{new_dir}-monthly" if now.day == 1
  File.rename("#{BASEDIR}/#{orig_dir}", "#{BASEDIR}/#{new_dir}")
  
  cleanup
end

def cleanup
  paths = Dir.glob("#{BASEDIR}/20*-daily*").select{ |path|
    File.directory? path
  }.select{ |path|
    path =~ %r|/\d{8}-\d{6}(-daily)?(-weekly)?(-monthly)?$|
  }.sort.reverse
  
  removes = [ true ] * paths.length
  
  ctr = 0
  paths.length.times do |i|
    if paths[i] =~ /-daily/
      removes[i] = false if ctr < 3
      ctr += 1
    end
  end
  
  ctr = 0
  paths.length.times do |i|
    if paths[i] =~ /-weekly/
      removes[i] = false if ctr < 2
      ctr += 1
    end
  end
  
  ctr = 0
  paths.length.times do |i|
    if paths[i] =~ /-monthly/
      removes[i] = false if ctr < 2
      ctr += 1
    end
  end
  
  paths.length.times do |i|
    if removes[i]
      $stderr.puts "rm -r #{paths[i]}"
      FileUtils.rm_r(paths[i])
    end
  end
  
end

srv = WEBrick::HTTPServer.new({
                                DocumentRoot: './',
                                BindAddress: '127.0.0.1',
                                Port: 8083,
                              })
srv.mount_proc '/begin' do |req, res|
  handle_begin(req, res)
end
srv.mount_proc '/file/' do |req, res|
  handle_file(req, res)
end
srv.mount_proc '/keep/' do |req, res|
  handle_keep(req, res)
end
srv.mount_proc '/finish' do |req, res|
  handle_finish(req, res)
end
srv.start
