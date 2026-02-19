FROM redis:7-alpine

# Redis with no persistence for CRS usage
CMD ["redis-server", "--save", "", "--appendonly", "no"]
