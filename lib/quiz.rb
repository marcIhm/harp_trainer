#
# Perform quiz and memorize
#

def do_quiz

  prepare_term
  start_kb_handler
  start_collect_freqs
  $ctl_can_next = true
  $ctl_can_loop = true
  $ctl_ignore_recording = $ctl_ignore_holes = $ctl_ignore_partial = false
  $write_journal = true
  journal_start
  
  first_round = true
  all_wanted_before = all_wanted = nil
  $all_licks, $licks = read_licks
  lick = lick_idx = lick_idx_before = lick_idx_iter = nil
  lick_cycle = false
  start_with = $opts[:start_with].dup
  puts
  puts "#{$licks.length} licks." if $mode == :memorize
  
  loop do   # forever until ctrl-c, sequence after sequence

    if first_round
      print "\n"
      print "\e[#{$term_height}H\e[K"
      print "\e[#{$term_height-1}H\e[K"
    else
      print "\e[#{$line_hint_or_message}H\e[K"
      print "\e[#{$line_call2}H\e[K"
      print "\e[#{$line_issue}H\e[0mListen ...\e[K"
      ctl_issue
    end

    #
    #  First compute and play the sequence that is expected
    #

    # check, if lick has changed
    if lick_idx && refresh_licks
      lick = $licks[lick_idx]
      all_wanted = lick[:holes]
      ctl_issue 'Refreshed licks'
    end

    # handle $ctl-commands from keyboard-thread, that probably come from a previous loop
    if $ctl_back # 
      if lick
        if !lick_idx_before || lick_idx_before == lick_idx
          print "\e[G\e[0m\e[32mNo previous lick; replay\e[K"
          sleep 1
        else
          lick_idx = lick_idx_before
          lick = $licks[lick_idx]
          all_wanted = lick[:holes]
        end
      else
        if !all_wanted_before || all_wanted_before == all_wanted
          print "\e[G\e[0m\e[32mNo previous sequence; replay\e[K"
          sleep 1
        else
          all_wanted = all_wanted_before
        end
      end
      $ctl_loop = true

    elsif $ctl_replay

    # nothing to do
      
    else # e.g. sequence done or $ctl_next: go to the next sequence
      all_wanted_before = all_wanted
      lick_idx_before = lick_idx

      do_write_journal = true

      # figure out holes to play
      if $mode == :quiz

        all_wanted = get_sample($num_quiz)
        jtext = all_wanted.join(' ')

      else # memorize

        if lick_idx_iter # continue with iteration through licks

          lick_idx_iter += 1
          if lick_idx_iter >= $licks.length
            if lick_cycle
              lick_idx_iter = 0
              ctl_issue 'Next cycle'
            else
              print "\e[#{$line_call2}H\e[K"
              puts "\nIterated through all #{$licks.length} licks.\n\n"
              exit
            end
          end
          lick_idx = lick_idx_iter

        elsif !start_with # most general case: choose random lick
          # avoid playing the same lick twice in a row
          if lick_idx_before
            lick_idx = (lick_idx + 1 + rand($licks.length - 1)) % $licks.length
          else
            lick_idx = rand($licks.length)
          end

        elsif start_with == 'print'
          print_lick_and_tag_info
          exit
          
        elsif start_with == 'dump'
          pp $all_licks
          exit
          
        elsif start_with == 'hist' || start_with == 'history'
          print_last_licks_from_journal $all_licks
          exit

        elsif %w(i iter iterate cycle).include?(start_with)
          lick_cycle = ( start_with == 'cycle' )
          lick_idx_iter = 0
          lick_idx = lick_idx_iter

        elsif (md = start_with.match(/^(\dlast|\dl)$/)) || start_with == 'last' || start_with == 'l'
          lick_idx = get_last_lick_idxs_from_journal[md  ?  md[1].to_i - 1  :  0]
          do_write_journal = false

        else # search lick by name and maybe iterate
          doiter = %w(,iterate ,iter ,i ,cycle).find {|x| start_with.end_with?(x)}
          lick_cycle = start_with.end_with?('cycle')
          start_with[-doiter.length .. -1] = '' if doiter

          lick_idx = $licks.index {|l| l[:name] == start_with}
          err "Unknown lick: '#{start_with}' (after applying options '--tags' and '--no-tags' and '--max-holes')" unless lick_idx

          lick_idx_iter = lick_idx if doiter

        end

        start_with = nil
        
        lick = $licks[lick_idx]
        all_wanted = lick[:holes]
        jtext = sprintf('Lick %s: ', lick[:desc]) + all_wanted.join(' ')

      end

      IO.write($journal_file, "#{jtext}\n\n", mode: 'a') if $write_journal && do_write_journal
      $ctl_loop = $opts[:loop]

    end
    $ctl_back = $ctl_next = $ctl_replay = false
    
    sleep 0.3

    if $mode == :quiz || !lick[:rec] || $ctl_ignore_recording || ($opts[:holes] && !$ctl_ignore_holes)
      play_holes all_wanted, first_round
    else
      play_recording lick, first_round
    end
    
    redo if $ctl_back || $ctl_next || $ctl_replay
    $ctl_ignore_recording = $ctl_ignore_holes = $ctl_ignore_partial = false

    print "\e[0m\e[32m and !\e[0m"
    sleep 0.5

    if first_round
      system('clear')
    else
      print "\e[#{$line_hint_or_message}H\e[K"
      print "\e[#{$line_call2}H\e[K"
    end
    full_seq_shown = false

    # precompute some values, that do not change during sequence
    min_sec_hold =  $mode == :memorize  ?  0.0  :  0.1
    lick_names = if $mode == :memorize
                   [sprintf(' (%s)', lick[:name]) ,
                    ' ' + lick[:name] ,
                    sprintf("\e[2m (%s)", lick[:name])]
                 else
                   ['','','']
                 end

    
    holes_with_scales = scaleify(all_wanted) if $conf[:comment] == :holes_all_with_scales

    #
    #  Now listen for user to play the sequence back correctly
    #

    begin   # while looping over one sequence

      round_start = Time.now.to_f
      $ctl_forget = false
      idx_refresh_comment_cache = comment_cache = nil
      clear_area_comment if $conf[:comment] == :holes_all_with_scales
      
      all_wanted.each_with_index do |wanted, idx|  # iterate over notes in sequence, i.e. one iteration while looping

        hole_start = Time.now.to_f
        pipeline_catch_up

        handle_holes(
          
          # lambda_issue
          -> () do      
            if $ctl_loop
              "\e[32mLoop\e[0m at #{idx+1} of #{all_wanted.length} notes" +
                lick_names[1] +
                ' ' # cover varying length of idx
            else
              if $num_quiz == 1 
                "Play the note you have heard !"
              else
                "Play note \e[32m#{idx+1}\e[0m of" +
                  " #{all_wanted.length} you have heard !" +
                  lick_names[0] + ' '
              end
            end 
          end,

          
          # lambda_good_done_was_good
          -> (played, since) {[played == wanted || musical_event?(wanted),  
                               $ctl_forget ||
                               ((played == wanted || musical_event?(wanted)) &&
                                (Time.now.to_f - since >= min_sec_hold )),
                               idx > 0 && played == all_wanted[idx-1] && played != wanted]}, 

          # lambda_skip
          -> () {$ctl_next || $ctl_back || $ctl_replay},  

          
          # lambda_comment
          -> (_, _, _, _, _, _, _) do
            if idx != idx_refresh_comment_cache
              idx_refresh_ccache = idx
              comment_cache = 
                if $conf[:comment] == :holes_all_with_scales
                  tabify_colorize($line_hint_or_message - $line_comment + 1, holes_with_scales, idx)
                else
                  largify(all_wanted, idx)
                end
            end
            comment_cache
          end,

          
          # lambda_hint
          -> (_) do
            hole_passed = Time.now.to_f - hole_start
            round_passed = Time.now.to_f - round_start
            
            hint = if $opts[:immediate] # show all holes right away
                     "\e[2mPlay:" +
                       if idx == 0
                         ''
                       else
                         ' ' + all_wanted[0 .. idx - 1].join(' ')
                       end +
                       "\e[0m\e[92m*\e[0m" +
                       all_wanted[idx .. -1].join(' ')
                   elsif all_wanted.length > 1 &&
                         hole_passed > 4 &&
                         # show holes earlier, if we showed them
                         # already for this seq
                         round_passed > ( full_seq_shown ? 3 : 6 ) * all_wanted.length
                     "\e[0mThe complete sequence is: #{all_wanted.join(' ')}" 
                     full_seq_shown = true
                   elsif hole_passed > 4
                     "\e[2mHint: Play \e[0m\e[32m#{wanted}\e[0m"
                   else
                     if idx > 0
                       isemi, itext = describe_inter(wanted, all_wanted[idx - 1])
                       if isemi
                         "Hint: Move " + ( itext ? "a #{itext}" : isemi )
                       end
                     end
                   end

            ( hint || '' ) + lick_names[2]
          end,
          
          
          # lambda_hole_for_inter
          -> (_, _) { idx > 0 && all_wanted[idx - 1] }

        )  # end of get_hole

        break if $ctl_next || $ctl_back || $ctl_replay || $ctl_forget

      end # notes in a sequence
      
      #
      #  Finally judge result
      #

      clear_area_comment if $conf[:comment] == :holes_all_with_scales
      if $ctl_forget
        if $conf[:comment] == :holes_all_with_scales
          clear_area_comment
          print "\e[#{$line_comment + 2}H\e[0m\e[32m   again"
        else
          print "\e[#{$line_comment}H\e[0m\e[32m"
          do_figlet 'again', 'smblock'
        end
        sleep 0.5
      else
        text = if $ctl_next
                 "next"
               elsif $ctl_back
                 "jump back"
               elsif $ctl_replay
                 "replay"
               else
                 ( full_seq_shown ? 'Yes ' : 'Great ! ' ) + all_wanted.join(' ')
               end
        if $conf[:comment] == :holes_all_with_scales
          clear_area_comment
          puts "\e[#{$line_comment + 2}H\e[0m\e[32m   " + text
        else
          print "\e[#{$line_comment}H\e[0m\e[32m"
          do_figlet text, 'smblock'
        end
        print "\e[0m"
        
        print "\e[#{$line_hint_or_message}H\e[K"
        unless $ctl_replay || $ctl_forget
          print "\e[0m#{$ctl_next || $ctl_back ? 'T' : 'Yes, t'}he sequence was: #{all_wanted.join(' ')} ... "
          print "\e[0m\e[32mand #{$ctl_loop ? 'again' : 'next'}\e[0m !\e[K"
          full_seq_shown = true
          sleep 1
        end
      end
      
    end while ( $ctl_loop || $ctl_forget) && !$ctl_back && !$ctl_next && !$ctl_replay # looping over one sequence

    print "\e[#{$line_issue}H#{''.ljust($term_width - $ctl_issue_width)}"
    first_round = false
  end # forever sequence after sequence
end
      
$sample_stats = Hash.new {|h,k| h[k] = 0}

def get_sample num
  # construct chains of holes within scale and added scale
  holes = Array.new
  # favor lower starting notes
  if rand > 0.5
    holes[0] = $scale_holes[0 .. $scale_holes.length/2].sample
  else
    holes[0] = $scale_holes.sample
  end

  what = Array.new(num)
  for i in (1 .. num - 1)
    ran = rand
    tries = 0
    if ran > 0.7
      what[i] = :nearby
      begin
        try_semi = $harp[holes[i-1]][:semi] + rand(-6 .. 6)
        tries += 1
        break if tries > 100
      end until $semi2hole[try_semi]
      holes[i] = $semi2hole[try_semi]
    else
      what[i] = :interval
      begin
        # semitone distances 4,7 and 12 are major third, perfect fifth
        # and octave respectively
        try_semi = $harp[holes[i-1]][:semi] + [4,7,12].sample * [-1,1].sample
        tries += 1
        break if tries > 100
      end until $semi2hole[try_semi]
      holes[i] = $semi2hole[try_semi]
    end
  end

  if $opts[:add_scales]
    # (randomly) replace notes with added ones and so prefer them 
    for i in (1 .. num - 1)
      if rand >= 0.6
        holes[i] = nearest_hole_with_flag(holes[i], :added)
        what[i] = :nearest_added
      end
    end
    # (randomly) make last note a root note
    if rand >= 0.6
      holes[-1] = nearest_hole_with_flag(holes[-1], :root)
      what[-1] = :nearest_root
    end
  end

  for i in (1 .. num - 1)
    # make sure, there is a note in every slot
    unless holes[i]
      holes[i] = $scale_holes.sample
      what[i] = :fallback
    end
    $sample_stats[what[i]] += 1
  end

  holes
end


def nearest_hole_with_flag hole, flag
  delta_semi = 0
  found = nil
  begin
    [delta_semi, -delta_semi].shuffle.each do |ds|
      try_semi = $harp[hole][:semi] + ds
      try_hole = $semi2hole[try_semi]
      if try_hole
        try_flags = $hole2flags[try_hole]
        found = try_hole if try_flags && try_flags.include?(flag)
      end
      return found if found
    end
    # no near hole found
    return nil if delta_semi > 8
    delta_semi += 1
  end while true
end


def play_holes all_holes, first_round
  ltext = "\e[2m(h for help) "

  if $opts[:partial] && !$ctl_ignore_partial
    holes, _, _ = select_and_calc_partial(all_holes, nil, nil)
  else
    holes = all_holes
  end
  IO.write($testing_log, all_holes.inspect + "\n", mode: 'a') if $opts[:testing]
  
  $ctl_skip = false
  holes.each_with_index do |hole, idx|

    if ltext.length - 4 * ltext.count("\e") > $term_width * 1.7 
      ltext = "\e[2m(h for help) "
      if first_round
        print "\e[#{$term_height}H\e[K"
        print "\e[#{$term_height-1}H\e[K"
      else
        print "\e[#{$line_hint_or_message}H\e[K"
        print "\e[#{$line_call2}H\e[K"
      end
    end
    if idx > 0
      if !musical_event?(hole) && !musical_event?(holes[idx - 1])
        isemi, itext = describe_inter(hole, holes[idx - 1])
        ltext += ' ' + ( itext || isemi ).tr(' ','') + ' '
      else
        ltext += ' '
      end
    end
    ltext += if musical_event?(hole)
               "\e[0m#{hole}\e[2m"
             elsif $opts[:immediate]
               "\e[0m#{hole},#{$harp[hole][:note]}\e[2m"
             else
               "\e[0m#{$harp[hole][:note]}\e[2m"
             end
    if $opts[:add_scales]
      part = '(' +
             $hole2flags[hole].map {|f| {added: 'a', root: 'r'}[f]}.compact.join(',') +
             ')'
      ltext += part unless part == '()'
    end

    if first_round
      print "\e[#{$term_height-1}H#{ltext.strip}\e[K"
    else
      print "\e[#{$line_call2}H\e[K"
      print "\e[#{$line_hint_or_message}H#{ltext.strip}\e[K"
    end

    if musical_event?(hole)
      sleep $opts[:fast]  ?  0.25  :  0.5
    else
      play_hole_and_handle_kb hole
    end

    if $ctl_show_help
      display_kb_help 'series of holes',first_round, <<~end_of_content
        SPACE: pause/continue 
        TAB,+: skip to end
      end_of_content
      $ctl_show_help = false
    end
    if $ctl_skip
      print "\e[0m\e[32m skip to end\e[0m"
      sleep 0.5
      break
    end
  end
end


def play_recording lick, first_round
  issue = "Lick \e[0m\e[32m" + lick[:name] + "\e[0m (h for help) ... " + lick[:holes].join(' ')
  if first_round
    print "\e[#{$term_height}H#{issue}\e[K"
  else
    print "\e[#{$line_hint_or_message}H#{issue}\e[K"
  end

  if $opts[:partial] && !$ctl_ignore_partial
    _, start, length = select_and_calc_partial([], lick[:rec_start], lick[:rec_length])
  else
    start, length = lick[:rec_start], lick[:rec_length]
  end
  skipped = play_recording_and_handle_kb lick[:rec], start, length, lick[:rec_key], first_round
  print skipped ? " skip rest" : " done"
end


def select_and_calc_partial all_holes, start_s, length_s
  start = start_s.to_f
  length = length_s.to_f
  if md = $opts[:partial].match(/^1\/(\d)@(b|x|e)$/)
    numh = (all_holes.length/md[1].to_f).round
    pl = length / md[1].to_f
    pl = [1,length].min if pl < 1
    ps = case md[2]
         when 'b'
           start
         when 'e'
           start + length - pl
         else
           start + pl * rand(md[1].to_i)/md[1].to_f
         end
  elsif md = $opts[:partial].match(/^(\d*\.?\d*)@(b|x|e)$/)
    err "Argument for option '--partial' should have digits before '@'; '#{$opts[:partial]}' does not" if md[1].length == 0
    numh = md[1].to_f.round
    pl = md[1].to_f
    pl = length if pl > length
    ps = case md[2]
         when 'b'
           start
         when 'e'
           start + length - pl
         else
           start + (length - pl) * rand
         end
  else
    err "Argument for option '--partial' must be like 1/3@b, 1/4@x, 1/2@e, 1@b, 2@x or 0.5@e but not '#{$opts[:partial]}'"
  end
  
  numh = 1 if numh == 0
  numh = all_holes.length if numh > all_holes.length
  holes = case md[2]
          when 'b'
            all_holes[0 .. numh-1]
          when 'e'
            all_holes[-numh .. -1]
          else
            pos = rand(all_holes.length - numh + 1)
            all_holes[pos .. pos+numh-1]
          end
  if start_s
    [holes, sprintf("%.1f",ps), sprintf("%.1f",pl)]
  else
    [holes, nil, nil]
  end
end


def tabify_colorize max_lines, holes_scales, idx_first_active
  lines = Array.new
  max_cell_len = holes_scales.map {|hs| hs.map(&:length).sum + 2}.max
  per_line = (($term_width * 0.8 - 4)/ max_cell_len).truncate
  line = '   '
  holes_scales.each_with_index do |hole_scale, idx|
    line += " \e[0m" +
            if idx < idx_first_active
              ' ' + "\e[0m\e[38;5;238m" + hole_scale[0] + hole_scale[1] + ':' + hole_scale[2]
            else
              hole_scale[0] +
                if idx == idx_first_active
                  "\e[0m\e[92m*"
                else
                  ' '
                end +
                sprintf("\e[0m\e[%dm", get_hole_color_inactive(hole_scale[1])) +
                hole_scale[1] + "\e[0m\e[38;5;238m" + ':' + hole_scale[2]
            end
    if idx > 0 && idx % per_line == 0
      lines << line
      line = '   '
      if lines.length >= max_lines - 1
        lines[-1] = lines[-1].ljust(per_line)
        lines[-1][-6 .. -1] = "\e[0m  ... "
        return lines
      end
      lines << ''
    end
  end
  lines << line + "\e[0m"
  lines << ''
end


def scaleify holes
  holes = holes.reject {|h| musical_event?(h)}
  holes_maxlen = holes.max_by(&:length).length
  abbrev_maxlen = holes.map {|hole| $hole2scale_abbrevs[hole]}.max_by(&:length).length
  holes.each.map {|hole| [' ' * (holes_maxlen - hole.length), hole, $hole2scale_abbrevs[hole].ljust(abbrev_maxlen)]}
end


def largify all_wanted, idx
  if $num_quiz == 1
    [ "\e[2m", '.  .  .', 'smblock', nil ]
  elsif $opts[:immediate] # show all unplayed
    hidden_holes = if idx > 8
                     ". . # . ."
                   else
                     ' .' * idx
                   end
    [ "\e[2m",
      'Play  ' + hidden_holes + all_wanted[idx .. -1].join(' '),
      'smblock',
      'play  ' + '--' * all_wanted.length,  # width_template
      :right ]  # truncate at
  else # show all played
    hidden_holes = if all_wanted.length - idx > 8
                     " _ _ # _ _" # abbreviation for long sequence of ' _'
                   else
                     ' _' * (all_wanted.length - idx)
                   end
    [ "\e[2m",
      'Yes  ' + all_wanted.slice(0,idx).join(' ') + hidden_holes,
      'smblock',
      'yes  ' + '--' * [6,all_wanted.length].min,  # width_template
      :left ]  # truncate at
  end
end
