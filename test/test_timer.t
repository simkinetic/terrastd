-- SPDX-FileCopyrightText: 2024 - 2025 René Hiemstra <rrhiemstar@gmail.com>
-- SPDX-FileCopyrightText: 2024 - 2025 Torsten Keßler <t.kessler@posteo.de>
--
-- SPDX-License-Identifier: MIT

import "terratest@v1/terratest"

if not __silent__ then

	local time = require("std@v0/timing")
	local uni = terralib.includec("unistd.h")
	local io = terralib.includec("stdio.h")

	terra main()
		var sw : time.default_timer
		sw:start()
		uni.usleep(2124)
		var t = sw:stop()
		io.printf("Sleep took %g s\n", t)
	end
	main()

end
