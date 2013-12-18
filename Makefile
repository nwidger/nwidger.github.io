CWD := $(shell pwd)

all: production

production:
	hugo -b http://nwidger.github.io/public

development:
	hugo -b file://$(CWD)/public

.PHONEY: production development
