--!strict
--[[
	StateMachine — универсальный конечный автомат (используется ИИ боссов).

	Состояние — таблица колбэков:
	  enter(ctx)   — при входе;
	  update(ctx)  — каждый кадр; вернуть имя следующего состояния, чтобы перейти (nil — остаться);
	  exit(ctx)    — при выходе.
	За один кадр допускается несколько переходов подряд (например, Neutral → Punish → Attack),
	но не больше MAX_TRANSITIONS_PER_STEP — защита от зацикливания.
]]

export type State<C> = {
	enter: ((ctx: C) -> ())?,
	update: (ctx: C) -> string?,
	exit: ((ctx: C) -> ())?,
}

export type Machine<C> = {
	states: { [string]: State<C> },
	current: string,
	frames: number, -- кадров в текущем состоянии
	context: C,
	transitions: number, -- всего переходов (для отладки и тестов)
	entries: { [string]: number }, -- сколько раз входили в каждое состояние
}

local MAX_TRANSITIONS_PER_STEP = 4

local StateMachine = {}

function StateMachine.new<C>(states: { [string]: State<C> }, initial: string, context: C): Machine<C>
	assert(states[initial], `Нет состояния {initial}`)
	local machine: Machine<C> = {
		states = states,
		current = initial,
		frames = 0,
		context = context,
		transitions = 0,
		entries = { [initial] = 1 },
	}
	local enter = states[initial].enter
	if enter then
		enter(context)
	end
	return machine
end

-- Немедленно перейти в состояние (выход из текущего, вход в новое).
function StateMachine.transition<C>(machine: Machine<C>, name: string)
	local target = machine.states[name]
	assert(target, `Нет состояния {name}`)
	local exit = machine.states[machine.current].exit
	if exit then
		exit(machine.context)
	end
	machine.current = name
	machine.frames = 0
	machine.transitions += 1
	machine.entries[name] = (machine.entries[name] or 0) + 1
	local enter = target.enter
	if enter then
		enter(machine.context)
	end
end

-- Шаг автомата: update текущего состояния и переходы.
function StateMachine.step<C>(machine: Machine<C>)
	for _ = 1, MAX_TRANSITIONS_PER_STEP do
		local nextName = machine.states[machine.current].update(machine.context)
		if nextName == nil or nextName == machine.current then
			break
		end
		StateMachine.transition(machine, nextName)
	end
	machine.frames += 1
end

return StateMachine
