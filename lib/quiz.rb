#
# Perform quiz
#

def do_quiz

  prepare_term
  puts "\n\nAgain and again: Hear #{$num_quiz} note(s) from the scale and then try to replay ..."
  [2,1].each do |c|
    puts c
    sleep 1
  end

  first_lap_at_all = true
  $ctl_can_next = true
  loop do   # forever, sequence after sequence

    all_wanted = $scale_holes.sample($num_quiz)
    sleep 0.3

    unless first_lap_at_all
      ctl_issue "SPACE to pause"
      print "\e[#{$line_hint}H" 
      puts_pad
      print "\e[#{$line_listen}H"
      puts_pad
    end

    all_wanted.each_with_index do |hole, idx|
      file = "#{$sample_dir}/#{$harp[hole][:note]}.wav"
      poll_and_handle_kb true
      if idx > 0
        isemi, itext = describe_inter(hole, all_wanted[idx - 1])
        print "\e[2m(" + ( itext || "#{isemi}" ) + ")\e[0m "
      end
      print "listen ... "
      play_sound file
    end
    print "\e[32mand !\e[0m"
    sleep 0.5
    print "\e[#{$line_listen}H" unless first_lap_at_all
    puts_pad
  
    system('clear') if first_lap_at_all
    full_hint_shown = false

    $ctl_loop = $opts[:loop]
    begin   # while looping over one sequence

      lap_start = Time.now.to_f
      all_wanted.each_with_index do |wanted, idx|  # iterate over notes in sequence, i.e. one lap while looping

        hole_start = Time.now.to_f
        get_hole(
          if $ctl_loop
            "Looping over #{all_wanted.length} notes; play them again and again ..."
          else
            if $num_quiz == 1 
              "Play the note you have heard !"
            else
              "Play note number \e[32m#{idx+1}\e[0m from the sequence of #{$num_quiz} you have heard !"
            end
          end,
          -> (played, since) {[played == wanted,  # lambda_good_done
                               played == wanted && 
                               Time.now.to_f - since > 0.5]}, # do not return okay immediately
          
          -> () {$ctl_next},  # lambda_skip
          
          -> (_, _) do  # lambda_comment_big
            if $num_quiz == 1
              [ '.  .  .', 'smblock' ]
            else
              [ 'Yes  ' + '*' * idx + '-' * (all_wanted.length - idx), 'smblock' ]
            end
          end,
          
          -> () do  # lambda_hint
            hole_passed = Time.now.to_f - hole_start
            lap_passed = Time.now.to_f - lap_start

            if all_wanted.length > 1 &&
               hole_passed > 4 &&
               lap_passed > ( full_hint_shown ? 3 : 6 ) * all_wanted.length
              print "The complete sequence is: #{all_wanted.join(' ')}\e[0m" 
              full_hint_shown = true
              puts_pad
            elsif hole_passed > 4
              print "Hint: Play \e[32m#{wanted}\e[0m"
              puts_pad
            else
              if idx > 0
                isemi, itext = describe_inter(wanted, all_wanted[idx - 1])
                print "\e[2mHint: Move "
                puts_pad ( itext ? "a #{itext}" : isemi )
              else
                puts_pad
              end
            end
          end,

          -> (_) { idx > 0 && all_wanted[idx - 1] })  # lambda_hole_for_inter

        print "\e[#{$line_comment_small}H"
        puts_pad

      end # notes in a sequence
        
      if $ctl_next
        print "\e[#{$line_issue}H"
        puts_pad '', true
        $ctl_loop = false
        first_lap_at_all = false
        next
      end
    
      print "\e[#{$line_comment_big}H"
      text = $ctl_next ? 'skipped' : ( full_hint_shown ? 'Yes' : 'Great !' )
      print "\e[32m"
      do_figlet text, 'smblock'
      print "\e[0m"
      
      print "\e[#{$line_comment_small}H"
      print "#{$ctl_next ? 'T' : 'Yes, t'}he sequence was: #{all_wanted.join(' ')}   ...   "
      puts_pad "\e[0m\e[32mand #{$ctl_loop ? 'again' : 'next'}\e[0m !"
      full_hint_shown = true
    
      sleep 1
    end while $ctl_loop  # looping over one sequence

    $ctl_next = false
    first_lap_at_all = false
  end # sequence after sequence
end

