CWD := $(shell pwd)

all: production

production:
	hugo -b http://nwidger.github.io/blog

development:
	hugo -b file://$(CWD)/blog

.PHONEY: production development
