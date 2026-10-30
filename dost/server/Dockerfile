FROM golang:1.24-alpine AS build
WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 go build -ldflags="-s -w" -o /dost .

FROM alpine:3.20
RUN apk add --no-cache ca-certificates tzdata && adduser -D -u 1000 dost
USER dost
COPY --from=build /dost /dost
ENV TZ=Asia/Ashgabat
EXPOSE 8080
ENTRYPOINT ["/dost"]
