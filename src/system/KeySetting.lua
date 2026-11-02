-- new line
-- ================================================================
-- dialog module constant var
-- ================================================================
-- new line
--¡Á¼ü
function button_cross()
	drawhide()
end
-- new line
--¡÷¼ü
function button_triangle()
	drawhistory()
end
-- new line
--¡õ¼ü
function button_square()
	drawhelp()
end
-- new line
--L¼ü
function button_left_trigger()
	drawauto()
	speakmode(speak_mode_auto)
end
-- new line
--R¼ü
function button_right_trigger()
	drawskip()
	speakmode(speak_mode_skip)
end
--start¼ü
function button_start()
	if call_menu_flag then
		pub_value[129]=0x0
		drawmenu()
	end
end
-- new line
--select¼ü
function button_select()
	drawconfig()
end
-- new line
-- new line
-- ================================================================
-- menu module constant var
-- ================================================================
function menu_callback()
	if menutest()==5 then
		allclear()
		stacknull()
		jump("am_start.ev")
		drawevent()
	elseif menutest()==1 then
		drawskip()
		speakmode(speak_mode_skip)
	elseif menutest()==2 then
		drawauto()
		speakmode(speak_mode_auto)
	elseif menutest()==3 then
		drawload()
	elseif menutest()==4 then
		drawsave()
	else drawevent() end
end