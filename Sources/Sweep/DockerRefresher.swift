import SweepCore

@MainActor
enum DockerRefresher {
    static func refresh(_ model: AppModel) async {
        guard !model.isRefreshingDocker else { return }
        model.setRefreshingDocker(true)
        defer { model.setRefreshingDocker(false) }
        let service = DockerService()
        let status = await service.status()
        let items = status.running ? await service.findJunk() : []
        model.mergeDockerItems(items, status: status)
    }
}
