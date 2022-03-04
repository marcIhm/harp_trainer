#
# Perform quiz
#

def do_quiz

  prepare_term
  start_kb_handler
  start_collect_freqs
  $ctl_can_next = true
  $ctl_can_journal = false
  $ctl_can_loop = true
  $ctl_can_change_comment = false
  
  first_lap = true
  all_wanted_before = all_wanted = nil
  puts
  
  loop do   # forever until ctrl-c, sequence after sequence

    unless first_lap
      print "\e[#{$line_issue}H\e[K" 
      ctl_issue
      print "\e[#{$line_hint_or_message}H\e[K" 
      print "\e[#{$line_call}H\e[K"
    end

    if $ctl_back
      if !all_wanted_before || all_wanted_before == all_wanted
        print "no previous sequence; restarting "
        sleep 1
      else
        all_wanted = all_wanted_before
        print "\e[32mto previous sequence\e[0m "
        sleep 1
      end
      $ctl_loop = true
    else
      all_wanted_before = all_wanted
      all_wanted = get_sample($num_quiz)
      $ctl_loop = $opts[:loop]
    end
    $ctl_back = $ctl_next = false
    
    sleep 0.3

    ltext = "\e[2m"
    all_wanted.each_with_index do |hole, idx|
      print "\e[#{$line_call}H" unless first_lap
      ltext = '' if ltext.length - 4 * ltext.count("\e") > $term_width * 0.7
      if idx > 0
        isemi, itext = describe_inter(hole, all_wanted[idx - 1])
        ltext += ' ' + ( itext || isemi ).tr(' ','') + ' '
      end
      ltext += "\e[0m#{$harp[hole][:note]}\e[2m"
      ltext += "(#{$hole2rem[hole]})" if $opts[:prefer] && $hole2rem[hole]
      print "\e[G#{ltext}\e[K"
      play_thr = Thread.new { play_sound this_or_equiv("#{$sample_dir}/%s.wav", $harp[hole][:note]) }
      begin
        sleep 0.1
        handle_kb_listen
      end while play_thr.alive?
      play_thr.join   # raises any errors from thread
      break if $ctl_back
    end
    redo if $ctl_back
    print "\e[0m\e[32m and !\e[0m"
    sleep 1

    if first_lap
      system('clear')
    else
      print "\e[#{$line_call}H\e[K"
    end
    full_hint_shown = false

    begin   # while looping over one sequence

      lap_start = Time.now.to_f

      all_wanted.each_with_index do |wanted, idx|  # iterate over notes in sequence, i.e. one lap while looping

        hole_start = Time.now.to_f
        pipeline_catch_up

        get_hole( -> () do
                    if $ctl_loop
                      "\e[32mLooping\e[0m over #{all_wanted.length} notes"
                    else
                      if $num_quiz == 1 
                        "Play the note you have heard !"
                      else
                        "Play note \e[32m#{idx+1}\e[0m of #{$num_quiz} you have heard !"
                      end
                    end
                  end,
          -> (played, since) {[played == wanted,  # lambda_good_done
                               played == wanted && 
                               Time.now.to_f - since > 0.5]}, # do not return okay immediately
          
          -> () {$ctl_next || $ctl_back},  # lambda_skip
          
          -> (_, _, _, _, _, _, _) do  # lambda_comment
                    if $num_quiz == 1
                      [ "\e[2m", '.  .  .', 'smblock', nil ]
                    else
                      [ "\e[2m", 'Yes  ' + (idx == 0 ? '' : all_wanted[0 .. idx - 1].join(' ')) + ' _' * (all_wanted.length - idx), 'smblock', 'yes' + '--' * all_wanted.length ]
                    end
                  end,
          
          -> (_) do  # lambda_hint
            hole_passed = Time.now.to_f - hole_start
            lap_passed = Time.now.to_f - lap_start
            
            if all_wanted.length > 1 &&
               hole_passed > 4 &&
               lap_passed > ( full_hint_shown ? 3 : 6 ) * all_wanted.length
              full_hint_shown = true
              "Solution: The complete sequence is: #{describe_sequence(all_wanted)}" 
            elsif hole_passed > 4
              "Hint: Play \e[32m#{wanted}\e[0m"
            else
              if idx > 0
                isemi, itext = describe_inter(wanted, all_wanted[idx - 1])
                if isemi
                  "Hint: Move " + ( itext ? "a #{itext}" : isemi )
                end
              end
            end
          end,

          -> (_, _) { idx > 0 && all_wanted[idx - 1] })  # lambda_hole_for_inter


      end # notes in a sequence

      if $ctl_next || $ctl_back
        print "\e[#{$line_issue}H#{''.ljust($term_width - $ctl_issue_width)}"
        first_lap = false
        next
      end
    
      print "\e[#{$line_comment}H"
      text = if $ctl_next
               "skip"
             elsif $ctl_back
               "jump back"
             else
               ( full_hint_shown ? 'Yes ' : 'Great ! ' ) + all_wanted.join(' ')
             end
      print "\e[32m"
      do_figlet text, 'smblock'
      print "\e[0m"
      
      print "\e[#{$line_hint_or_message}H\e[K"
      print "#{$ctl_next || $ctl_back ? 'T' : 'Yes, t'}he sequence was: #{describe_sequence(all_wanted)}   ...   "
      print "\e[0m\e[32mand #{$ctl_loop ? 'again' : 'next'}\e[0m !\e[K"
      full_hint_shown = true
    
      sleep 1
    end while $ctl_loop && !$ctl_back && !$ctl_next  # looping over one sequence

    first_lap = false
  end # sequence after sequence
end

      
$sample_stats = Hash.new {|h,k| h[k] = 0}

def get_sample num
  # construct chains of holes within scale using one of these:
  # - random holes from the scale
  # - intervals within an octave
  # - named intervals
  holes = Array.new
  holes[0] = $scale_holes.sample
  semi2hole = $scale_holes.map {|hole| [$harp[hole][:semi], hole]}.to_h

  what = Array.new(num)
  for i in (1 .. num - 1)
    ran = rand
    tries = 0
    if ran > 0.7
      what[i] = :nearby
      begin
        try_semi = $harp[holes[i-1]][:semi] + rand(12) - 6
        tries += 1
        break if tries > 100
      end until semi2hole[try_semi]
      holes[i] = semi2hole[try_semi]
    else
      what[i] = :interval
      begin 
        try_semi = $harp[holes[i-1]][:semi] + [4,7,12].sample * ( 2 * rand(2) - 1 )
        tries += 1
        break if tries > 100
      end until semi2hole[try_semi]
      holes[i] = semi2hole[try_semi]
    end
  end

  if $opts[:prefer]
    for i in (1 .. num - 1)
      if rand >= 0.5
        holes[i] = nearest_hole_with_remark(holes[i], 'pref', semi2hole)
        what[i] = :nearest_pref
      end
    end
    if rand >= 0.5
      holes[-1] = nearest_hole_with_remark(holes[-1], 'root', semi2hole)
      what[-1] = :nearest_root
    end
  end

  for i in (1 .. num - 1)
    unless holes[i]
      holes[i] = $scale_holes.sample
      what[i] = :fallback
    end
    $sample_stats[what[i]] += 1
  end

  File.write('sample_stats', "\n#{Time.now}:\n#{$sample_stats.inspect}\n", mode: 'a') if $opts[:debug]
  holes
end


def nearest_hole_with_remark hole, remark, semi2hole
  delta_semi = 0
  found = nil
  begin
    [delta_semi, -delta_semi].each do |ds|
      try_semi = $harp[hole][:semi] + ds
      try_hole = semi2hole[try_semi]
      if try_hole
        try_rem = $hole2rem[try_hole]
        found = try_hole if try_rem && try_rem[remark]
      end
      break if found
    end
    return nil if delta_semi > 8
    delta_semi += 1
  end until found
  found
end


def describe_sequence holes
  desc = holes[0]
  holes.each_cons(2) do |h1, h2|
    di = describe_inter(h1,h2)
    desc += " \e[2m(#{di[1] || di[0]})\e[0m #{h2} "
  end
  desc.rstrip
end
  
