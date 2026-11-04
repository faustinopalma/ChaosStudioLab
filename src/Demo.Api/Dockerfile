FROM mcr.microsoft.com/dotnet/sdk:10.0-noble AS build
WORKDIR /src
COPY Demo.Api.csproj ./
RUN dotnet restore Demo.Api.csproj
COPY . ./
RUN dotnet publish Demo.Api.csproj --configuration Release --output /out --no-restore

FROM mcr.microsoft.com/dotnet/aspnet:10.0-noble AS runtime
WORKDIR /app
COPY --from=build /out ./
COPY chaos-readiness-fault /app/chaos-readiness-fault
RUN chmod 0555 /app/chaos-readiness-fault \
    && mkdir -p /tmp \
    && chown app:app /tmp
USER app
ENV ASPNETCORE_URLS=http://+:8080 \
    ASPNETCORE_HTTP_PORTS=8080 \
    Chaos__ReadinessFaultPath=/tmp/csl-readiness-fault.json
EXPOSE 8080
ENTRYPOINT ["dotnet", "Demo.Api.dll"]
