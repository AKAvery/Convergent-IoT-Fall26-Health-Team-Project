import Testing
@testable import Models

@Suite struct AngleTests {
    @Test func boxFacings() {
        #expect(BoxPosition.front.facingDeg == 0)
        #expect(BoxPosition.right.facingDeg == 90)
        #expect(BoxPosition.back.facingDeg == 180)
        #expect(BoxPosition.left.facingDeg == 270)
    }

    @Test func normalized() {
        #expect(Azimuth.normalized(0) == 0)
        #expect(Azimuth.normalized(360) == 0)
        #expect(Azimuth.normalized(-90) == 270)
        #expect(Azimuth.normalized(450) == 90)
        #expect(Azimuth.normalized(-720) == 0)
        let tiny = Azimuth.normalized(-0.00001)
        #expect(tiny >= 0 && tiny < 360)
    }

    @Test func difference() {
        #expect(Azimuth.difference(0, 90) == 90)
        #expect(Azimuth.difference(350, 10) == 20)
        #expect(Azimuth.difference(10, 350) == 20)
        #expect(Azimuth.difference(0, 180) == 180)
        #expect(Azimuth.difference(90, 270) == 180)
        #expect(Azimuth.difference(-90, 270) == 0)
    }
}
