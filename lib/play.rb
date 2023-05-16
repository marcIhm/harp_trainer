#
# Play from the commandline
#

def do_play to_play
  $all_licks, $licks = read_licks
  $ctl_can[:loop_loop] = true
  $ctl_can[:lick_lick] = true
  $ctl_rec[:lick_lick] = false
  
  trace_text = nil

  make_term_immediate

  puts "\nType is #{$type}, key of #{$key}, scale #{$scale}, #{$licks.length} licks."
  puts

  extra_allowed = %w(pitch all-licks inter interval)
  holes, lnames, snames, extra, args_for_extra = partition_to_play_or_print(to_play, extra_allowed, true)
  extra = Set.new(extra).to_a
  err "Option '--start-with' only useful when playing 'all-licks'" if $opts[:start_with] && !extra.include?('all-licks')

  #
  #  Actually play
  #
  
  if holes.length > 0

    play_holes holes, true, true

  elsif snames.length > 0

    snames.each do |sname|
      scale_holes, _, _, _ = read_and_parse_scale_simple(sname)
      play_holes scale_holes, true, true
      trace_text = sprintf('Scale %s: ', sname) + scale_holes.join(' ')
      IO.write($trace_file, "#{trace_text}\n\n", mode: 'a')
    end
      
  elsif lnames.length > 0

    lnames.each do |lname|
      lick = $licks.find {|l| l[:name] == lname}
      trace_lick(lick)
      play_and_print_lick lick
    end

  elsif extra.length > 0

    err "only one of #{extra_allowed} is allowed" if extra.length > 1
    if extra[0] == 'pitch'
      play_adjustable_pitch

    elsif extra[0] == 'interval' || extra[0] == 'inter'

      s1, s2 = normalize_interval(args_for_extra)

      play_interval s1, s2
        
    elsif extra[0] == 'all-licks'
      if $opts[:iterate] == :random
        lick_idx = nil
        loop do
          # avoid playing the same lick twice in a row
          if lick_idx
            lick_idx = (lick_idx + 1 + rand($licks.length - 1)) % $licks.length
          else
            lick_idx = rand($licks.length)
          end
          trace_lick($licks[lick_idx])
          play_and_print_lick $licks[lick_idx]
          maybe_wait_for_key
        end
      else
        sw = $opts[:start_with]
        idx = if sw 
                if (md = sw.match(/^(\dlast|\dl)$/)) || sw == 'last' || sw == 'l'
                  # start with lick from history
                  get_last_lick_idxs_from_trace($licks)[md  ?  md[1].to_i - 1  :  0]
                else
                  (0 ... $licks.length).find {|i| $licks[i][:name] == sw} or fail "Unknown lick #{sw} given for option '--start-with'" 
                end
              else
                0
              end
      
        loop do
          $licks.rotate(idx).each do |lick|
            trace_lick(lick)
            play_and_print_lick lick
            maybe_wait_for_key
          end
        end
      end
    else
      fail "Internal error"
    end
  else
    fail "Internal error"
  end
end


def partition_to_play_or_print to_p, extra_allowed = [], extra_takes_args = false

  holes = []
  lnames = []
  snames = []
  extra = []
  args_for_extra = []
  other = []
  all_lnames = $licks.map {|l| l[:name]}
  all_snames = scales_for_type($type)
  extra_seen = false
  to_p.join(' ').split.each do |tp| # allow -1 (oct) +2 to be passed as '-1 (oct) +2'

    if musical_event?(tp)
      holes << tp
    elsif $harp_holes.include?(tp) && !extra_seen
      holes << tp
    elsif $harp_notes.include?(tp) && !extra_seen
      holes << $note2hole[tp]
    elsif all_lnames.include?(tp)
      lnames << tp
    elsif all_snames.include?(tp)
      snames << tp
    elsif (md = tp.match(/^(\dlast|\dl)$/)) || tp == 'last' || tp == 'l'
      lnames << $all_licks[get_last_lick_idxs_from_trace($all_licks)[md  ?  md[1].to_i - 1  :  0] || 0][:name]
    elsif extra_allowed.include?(tp)
      extra << tp
      extra_seen = true
    elsif extra_seen && extra_takes_args
      args_for_extra << tp
    else
      other << tp
    end
  end

  #
  # Check results for consistency
  # 

  sources_count = [holes, lnames, snames, extra].select {|s| s.length > 0}.length

  if other.length > 0 || sources_count == 0
    puts
    if other.length == 0
      puts 'Nothing to play or print; please specify any of:'
    else
      puts "Cannot understand these arguments: #{other};"
      puts 'they are none of (exact match required):'
    end
    puts "\n- musical events in () or []"
    puts "\n- holes:"
    print_in_columns $harp_holes, 4
    puts "\n- notes:"
    print_in_columns $harp_notes, 4
    puts "\n- scales:"
    print_in_columns all_snames, 4
    puts "\n- licks:"
    print_in_columns all_lnames, 4
    if extra_allowed.length > 0
      puts "\n- extra:"
      print_in_columns extra_allowed, 4
    end
    puts
    err 'See above'
  end
  
  if sources_count > 1
    puts "The following types of arguments are present,\nbut ONLY ONE OF THEM can be handled at a time:"
    puts "- holes (maybe converted from given notes): #{holes}" if holes.length > 0
    puts "- scales: #{snames}" if snames.length > 0
    puts "- licks: #{lnames}" if lnames.length > 0
    err 'See above'
  end

  [holes, lnames, snames, extra, args_for_extra]

end


def hole_or_note_or_semi hns

  types = Array.new
  values = Array.new

  # check if argument is interval or absolute note or hole or event
  # many of them

  # hole ?
  if $harp_holes.include?(hns)
    types << :abs
    values << note2semi($hole2note[hns])
  end

  # note ?
  begin
    values << note2semi(hns)
    types << :abs
  rescue ArgumentError
  end

  # named interval ?
  inters = Hash.new
  $intervals.each do |k,vv|
    vv.each do |v|
      next if v[' ']
      inters[v.downcase] = k
    end
  end
  if inters[hns]
    types << :diff
    values << inters[hns].to_i
  end

  # interval in semitones ?
  if hns.match(/^[+-]?\d+(st)?$/)
    types << :diff
    values << hns.to_i
  end

  fail "Internal error: #{types}" if types.length >= 3
  
  if types.length == 0
    inters_desc = inters.keys.map {|nm| "#{nm}(=#{inters[nm]}st)"}.join(', ')
    err "Given argument #{hns} is none of these:\n" +
        "  - numeric interval\e[2m, e.g. 12st or -3\n" +
        "\e[0m  - named interval\e[2m, i.e. one of: " + inters_desc + "\n" +
        "\e[0m  - hole\e[2m, i.e. one of: " + $harp_holes.join(', ') + "\n" +
        "\e[0m  - note\e[2m, e.g. c4 or d5\e[0m"
  end

  return types, values
end


def normalize_interval args

  err "Need two arguments, to play or print an interval:\n" +
      "  - a base-note or base-hole, e.g. 'c4' or '+2'\n" +
      "  - a difference in semitones, either as a number or as a name, e.g. '12st' or 'oct'\n" unless args.length == 2

  args.map!(&:downcase)
      
  tt = Array.new
  vv = Array.new
  args.each do |arg|
    t, v = hole_or_note_or_semi(arg)
    tt << t
    vv << v
  end
  s1 = s2 = 0
  case tt
  when [[:abs, :diff], [:abs, :diff]]
    err "Both arguments #{args} can be interpreted as note or hole or as a differences in semitones; please remove ambiguity by appending 'st' to the interval"
  when [[:diff], [:diff]]
    err "You specified two semitone-differences but no base note: #{args}"
  when [[:abs, :diff], [:diff]], [[:abs], [:diff]]
    s1 = vv[0][0]
    s2 = s1 + vv[1][0]
  when [[:diff], [:abs, :diff]], [[:diff], [:abs]]
    s1 = vv[1][0]
    s2 = s1 + vv[0][0]
  when [[:abs], [:abs]]
    s1 = vv[0][0]
    s2 = vv[1][0]
  else
    fail "Internal error: #{types}"
  end

  return s1, s2
end


def play_and_print_lick lick
  sleep 1 if $ctl_rec[:loop_loop]
  if lick[:rec] && !$opts[:holes] && !$opts[:reverse]
    puts "Lick #{lick[:name]} (h for help)\n" + lick[:holes].join(' ')
    print "\e[0m\e[2m"
    puts "Tags: #{lick[:tags].join(', ')}" if lick[:tags]
    puts "Desc: #{lick[:desc]}" unless lick[:desc].to_s.empty?
    print "\e[0m"
    play_recording_and_handle_kb lick[:rec], lick[:rec_start], lick[:rec_length], lick[:rec_key], true
  else
    if $opts[:reverse]
      puts "Lick #{lick[:name]} in reverse (h for help)"
      play_holes lick[:holes].reverse, true, true
    else
      puts "Lick #{lick[:name]} (h for help)"
      play_holes lick[:holes], true, true
    end
  end
  puts
end

def maybe_wait_for_key
  if $ctl_rec[:lick_lick]
    puts "\e[0m\e[2mContinuing with next lick without waiting for key ('c' to toggle)\e[0m"
    sleep 0.5
  else
    puts "\e[0m\e[2m" +
         "Press any key for next lick, especially:\n" +
         "  c: continue without further questions\n" +
         "  L: loop over next and all licks until pressed again " +
         ( $ctl_rec[:loop_loop]  ?  "(already ON)"  :  "(currently OFF)" ) +
         "\e[0m"
    char = $ctl_kb_queue.deq
    $ctl_rec[:lick_lick] = !$ctl_rec[:lick_lick] if char == 'c'
    $ctl_rec[:loop_loop] = !$ctl_rec[:loop_loop] if char == 'L'
    puts
  end
end


def trace_lick lick
  trace_text = sprintf('Lick %s: ', lick[:name]) + lick[:holes].join(' ')
  IO.write($trace_file, "#{trace_text}\n\n", mode: 'a')
end    
  
