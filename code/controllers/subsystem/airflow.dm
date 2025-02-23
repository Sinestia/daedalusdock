SUBSYSTEM_DEF(airflow)
	name = "Air (Airflow)"
	wait = 1
	flags = SS_NO_INIT|SS_TICKER
	priority = FIRE_PRIORITY_AIRFLOW
	runlevels = RUNLEVEL_GAME|RUNLEVEL_POSTGAME

	var/static/tmp/list/processing = list()
	var/static/tmp/list/current = list()


/datum/controller/subsystem/airflow/Recover()
	current.Cut()

/datum/controller/subsystem/airflow/stat_entry(msg)
	msg += "P: [length(processing)] "
	msg += "C: [length(current)]"
	return ..()

/datum/controller/subsystem/airflow/fire(resumed, no_mc_tick)
	if (!resumed)
		current = processing.Copy()

	var/atom/movable/target

	while(length(current))
		if (MC_TICK_CHECK)
			return
		target = current[length(current)]
		current.len--

		if (target.airflow_speed <= 0)
			Dequeue(target)
			continue

		if (!isturf(target.loc))
			Dequeue(target)
			continue

		if (target.airflow_process_delay > 0)
			target.airflow_process_delay -= 1
			continue

		else if (target.airflow_process_delay)
			target.airflow_process_delay = 0

		target.airflow_speed = min(target.airflow_speed, 15)
		target.airflow_speed -= zas_settings.airflow_speed_decay

		if (target.airflow_skip_speedcheck)
			goto AfterSpeedcheck

		if (target.airflow_speed > 7)
			if (target.airflow_time++ >= target.airflow_speed - 7)
				target.airflow_skip_speedcheck = TRUE
				continue
		else
			target.airflow_process_delay = max(1, 10 - (target.airflow_speed + 3))
			target.airflow_skip_speedcheck = TRUE
			continue

		AfterSpeedcheck:

		target.airflow_skip_speedcheck = FALSE

		if (!target.airflow_dest || target.loc == target.airflow_dest)
			target.airflow_dest = locate(min(max(target.x + target.airflow_xo, 1), world.maxx), min(max(target.y + target.airflow_yo, 1), world.maxy), target.z)

		if ((target.x == 1) || (target.x == world.maxx) || (target.y == 1) || (target.y == world.maxy))
			Dequeue(target)
			continue

		if(!target.airflow_old_density && target.airflow_speed > zas_settings.airflow_speed_for_density)
			target.set_density(TRUE)

		target.moving_by_airflow = TRUE

		var/olddir = target.dir
		step_towards(target, target.airflow_dest)

		target.dir = olddir
		target.moving_by_airflow = FALSE
		target.airborne_acceleration++

		if(!target.airflow_old_density)
			target.set_density(FALSE)

		ADD_TRAIT(target, TRAIT_EXPERIENCING_AIRFLOW, AIRFLOW_TRAIT)

/datum/controller/subsystem/airflow/proc/Enqueue(atom/movable/to_add)
	if(!can_fire)
		return
	processing += to_add
	RegisterSignal(to_add, COMSIG_PARENT_QDELETING, PROC_REF(HandleDel))

/datum/controller/subsystem/airflow/proc/Dequeue(atom/movable/to_remove)
	processing -= to_remove
	UnregisterSignal(to_remove, COMSIG_PARENT_QDELETING)

	REMOVE_TRAIT(to_remove, TRAIT_EXPERIENCING_AIRFLOW, AIRFLOW_TRAIT)
	to_remove.airflow_dest = null
	to_remove.airflow_speed = 0
	to_remove.airflow_time = 0
	to_remove.airflow_skip_speedcheck = FALSE
	to_remove.airborne_acceleration = 0

/datum/controller/subsystem/airflow/proc/HandleDel(datum/source)
	SIGNAL_HANDLER
	processing -= source

/atom/movable/proc/prepare_airflow(strength)
	if (!airflow_dest || airflow_speed < 0 || last_airflow > world.time - zas_settings.airflow_delay)
		return FALSE
	if (airflow_speed)
		airflow_speed = strength / max(get_dist(src, airflow_dest), 1)
		return FALSE
	if(!check_airflow_movable(strength*10)) //Repel/Gotoairflowdest() divide the differential by a max of 10, so we're undoing that here
		return FALSE
	if (airflow_dest == loc)
		step_away(src, loc)
	if (ismob(src))
		to_chat(src, span_warning("You are pushed away by a rush of air!"))

	last_airflow = world.time

	var/airflow_falloff = 9 - sqrt((x - airflow_dest.x) ** 2 + (y - airflow_dest.y) ** 2)
	if (airflow_falloff < 1)
		airflow_dest = null
		return FALSE

	airflow_speed = min(max(strength * (9 / airflow_falloff), 1), 9)
	airflow_old_density = src.density
	return TRUE


/atom/movable/proc/GotoAirflowDest(strength)
	if (!prepare_airflow(strength))
		return
	airflow_xo = airflow_dest.x - x
	airflow_yo = airflow_dest.y - y
	airflow_dest = null
	SSairflow.Enqueue(src)

/atom/movable/proc/RepelAirflowDest(strength)
	if (!prepare_airflow(strength))
		return
	airflow_xo = -(airflow_dest.x - x)
	airflow_yo = -(airflow_dest.y - y)
	airflow_dest = null
	SSairflow.Enqueue(src)
