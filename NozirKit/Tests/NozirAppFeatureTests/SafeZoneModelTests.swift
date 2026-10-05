import Foundation
import Testing
import NozirLocation
import NozirNetworking
@testable import NozirAppFeature

private let childId = UUID()
private let schoolId = UUID()

@MainActor
private func setup(_ script: FakeLocation.Script, zoneId: UUID? = nil) -> (SafeZoneModel, FakeLocation) {
    let fake = FakeLocation(script)
    return (SafeZoneModel(childId: childId, zoneId: zoneId, location: fake), fake)
}

private func scriptWithSchool() -> FakeLocation.Script {
    var script = FakeLocation.Script()
    script.zones[childId] = .success([zone("Maktab", for: childId, id: schoolId, radius: 300)])
    return script
}

@MainActor
@Suite struct SafeZoneModelTests {
    @Test func aNewZoneStartsOnTheChildsLastFix() async {
        var script = FakeLocation.Script()
        script.locations[childId] = [.success(fixAt())]
        let (model, _) = setup(script)

        await model.load()

        #expect(!model.isEditing)
        #expect(model.centre == Coordinate(latitude: 41.3111, longitude: 69.2797))
        #expect(model.radius == 200)
        #expect(model.notifyOnEnter)
        #expect(!model.notifyOnExit)
        #expect(model.hint == .needsName)
        model.updateName("Maktab")
        #expect(model.hint == .centredOnLastFix)
        #expect(model.canSave)
    }

    @Test func withoutAFixThePlaceMustBeChosen() async {
        let (model, _) = setup(FakeLocation.Script())

        await model.load()
        model.updateName("Uy")

        #expect(model.centre == nil)
        #expect(model.hint == .needsPlace)
        #expect(!model.canSave)

        model.place(at: Coordinate(latitude: 41.2, longitude: 69.1))

        #expect(model.hint == nil)
        #expect(model.canSave)
    }

    @Test func aBlankNameCannotBeSavedAndANameStopsAtSixty() async {
        var script = FakeLocation.Script()
        script.locations[childId] = [.success(fixAt())]
        let (model, _) = setup(script)
        await model.load()

        model.updateName("   ")
        #expect(!model.canSave)

        model.updateName(String(repeating: "a", count: 70))
        #expect(model.name.count == 60)
    }

    @Test func theRadiusStaysWithinItsRange() async {
        let (model, _) = setup(FakeLocation.Script())

        model.updateRadius(10)
        #expect(model.radius == 50)
        model.updateRadius(9000)
        #expect(model.radius == 5000)
    }

    @Test func savingANewZonePostsItForTheChild() async {
        var script = FakeLocation.Script()
        script.locations[childId] = [.success(fixAt())]
        script.create = [.success(zone("Maktab", for: childId))]
        let (model, fake) = setup(script)
        await model.load()
        model.updateName(" Maktab ")

        await model.save()

        #expect(model.wasSaved)
        #expect(await fake.calls.last == "create")
        #expect(await fake.drafts == [SafeZoneDraft(name: "Maktab", latitude: 41.3111, longitude: 69.2797, radiusMeters: 200, notifyOnEnter: true, notifyOnExit: false)])
    }

    @Test func anExistingZoneOpensAsStoredAndSavesOnlyWhenChanged() async {
        var script = scriptWithSchool()
        script.update = [.success(zone("Maktab 2", for: childId, id: schoolId))]
        let (model, fake) = setup(script, zoneId: schoolId)

        await model.load()

        #expect(model.isEditing)
        #expect(model.name == "Maktab")
        #expect(model.radius == 300)
        #expect(model.centre == Coordinate(latitude: 41.30, longitude: 69.25))
        #expect(model.hint == nil)
        #expect(!model.canSave)

        model.updateName("Maktab 2")
        await model.save()

        #expect(model.wasSaved)
        #expect(await fake.zoneIds == [schoolId])
        #expect(await fake.drafts.first?.name == "Maktab 2")
    }

    // Review Focus 3.
    @Test func aZoneGoneElsewhereIsNotFound() async {
        var script = FakeLocation.Script()
        script.zones[childId] = .success([])
        let (model, _) = setup(script, zoneId: schoolId)

        await model.load()

        #expect(model.isMissing)
        #expect(model.message == .notFound)
        #expect(!model.canSave)
    }

    @Test func theZoneLimitIsSaid() async {
        var script = FakeLocation.Script()
        script.locations[childId] = [.success(fixAt())]
        script.create = [.failure(.server(status: 409, error: ApiError(code: .safeZoneLimitReached)))]
        let (model, _) = setup(script)
        await model.load()
        model.updateName("Maktab")

        await model.save()

        #expect(!model.wasSaved)
        #expect(model.message == .safeZoneLimitReached)
        #expect(!model.isSaving)
    }

    @Test func aFreePlanCannotAddAZone() async {
        var script = FakeLocation.Script()
        script.locations[childId] = [.success(fixAt())]
        script.create = [.failure(.server(status: 403, error: ApiError(code: .subscriptionRequired)))]
        let (model, _) = setup(script)
        await model.load()
        model.updateName("Maktab")

        await model.save()

        #expect(model.message == .subscriptionRequired)
        #expect(!model.wasSaved)
    }

    @Test func deletingAsksFirst() async {
        var script = scriptWithSchool()
        script.delete = [.success(())]
        let (model, fake) = setup(script, zoneId: schoolId)
        await model.load()

        model.askToDelete()
        #expect(model.deletion == .confirming)
        model.cancelDelete()
        #expect(model.deletion == .idle)
        #expect(await fake.calls.contains("delete") == false)

        model.askToDelete()
        await model.confirmDelete()

        #expect(model.wasDeleted)
        #expect(await fake.zoneIds == [schoolId])
    }

    @Test func aFailedDeleteGoesBackToTheQuestion() async {
        var script = scriptWithSchool()
        script.delete = [.failure(offline)]
        let (model, _) = setup(script, zoneId: schoolId)
        await model.load()
        model.askToDelete()

        await model.confirmDelete()

        #expect(!model.wasDeleted)
        #expect(model.deletion == .confirming)
        #expect(model.message == .noConnection)
    }

    @Test func aNewZoneCannotBeDeleted() async {
        let (model, _) = setup(FakeLocation.Script())
        await model.load()

        model.askToDelete()

        #expect(model.deletion == .idle)
    }

    @Test func aFailedLoadWhileEditingIsNotAFormToSave() async {
        var script = FakeLocation.Script()
        script.zones[childId] = .failure(offline)
        let (model, fake) = setup(script, zoneId: schoolId)

        await model.load()
        model.updateName("Blank")
        model.place(at: Coordinate(latitude: 41.2, longitude: 69.1))

        #expect(model.loadFailed)
        #expect(model.message == .noConnection)
        #expect(model.draft == nil)
        #expect(!model.canSave)
        await model.save()
        #expect(await fake.calls.contains("update") == false)
        model.askToDelete()
        #expect(model.deletion == .idle)
    }

    @Test func retryAfterAFailedLoadLoadsTheZone() async {
        var script = FakeLocation.Script()
        script.zones[childId] = .failure(offline)
        let (model, fake) = setup(script, zoneId: schoolId)
        await model.load()

        await fake.add { $0.zones[childId] = .success([zone("Maktab", for: childId, id: schoolId, radius: 300)]) }
        await model.load()

        #expect(!model.loadFailed)
        #expect(model.message == nil)
        #expect(model.name == "Maktab")
        #expect(model.radius == 300)
    }

    @Test func loadingAgainKeepsTheEditsInProgress() async {
        let (model, _) = setup(scriptWithSchool(), zoneId: schoolId)
        await model.load()
        model.updateName("Edited")

        await model.load()

        #expect(model.name == "Edited")
    }

    @Test func aZoneAlreadyGoneCountsAsDeleted() async {
        var script = scriptWithSchool()
        script.delete = [.failure(notFound)]
        let (model, _) = setup(script, zoneId: schoolId)
        await model.load()
        model.askToDelete()

        await model.confirmDelete()

        #expect(model.wasDeleted)
        #expect(model.message == nil)
    }

    @Test func saveAndDeleteDoNotOverlap() async {
        let (model, _) = setup(scriptWithSchool(), zoneId: schoolId)
        await model.load()
        model.askToDelete()
        model.updateName("Changed")
        #expect(!model.canSave)

        model.cancelDelete()
        #expect(model.canSave)
    }
}
