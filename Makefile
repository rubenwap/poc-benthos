up:
	docker-compose up -d

down:
	docker-compose down

run:
	docker-compose run benthos -c ./pipeline/benthos.yml