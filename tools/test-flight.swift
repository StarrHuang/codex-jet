import Foundation
import ResetCore

private func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    precondition(condition(), message)
}

@main struct FlightTests {
    static func main() {
        let missing = RoadsterFlightState(remainingPercent: nil)
        check(missing.remainingPercent == nil && missing.liftFraction == nil,
              "missing balance must not imply an altitude")
        let stale = RoadsterFlightState(remainingPercent: 72, stale: true)
        check(stale.remainingPercent == nil && stale.liftFraction == nil,
              "stale balance must hide the capacity and altitude inference")
        let empty = RoadsterFlightState(remainingPercent: 0)
        let partial = RoadsterFlightState(remainingPercent: 35)
        let full = RoadsterFlightState(remainingPercent: 100)
        check(empty.liftFraction == 0 && empty.remainingPercent == 0,
              "zero balance must place the car on the pad")
        check(partial.liftFraction == 0.35 && partial.remainingPercent == 35,
              "altitude must map directly to actual remaining balance")
        check(full.liftFraction == 1 && full.remainingPercent == 100,
              "full balance must reach configured maximum altitude")
        check(partial.liftFraction! > empty.liftFraction! && full.liftFraction! > partial.liftFraction!,
              "increasing balance must raise the Roadster monotonically")
        check(RoadsterFlightState(remainingPercent: -5).liftFraction == 0,
              "visual altitude must clamp below zero")
        check(RoadsterFlightState(remainingPercent: 125).liftFraction == 1,
              "visual altitude must clamp above one hundred percent")
        check(RoadsterFlightState(remainingPercent: .nan).liftFraction == nil,
              "non-finite balance must remain unknown")
        let slow = RoadsterFlightState(remainingPercent: 60, ratePerHour: 2)
        let medium = RoadsterFlightState(remainingPercent: 60, ratePerHour: 10)
        let fast = RoadsterFlightState(remainingPercent: 60, ratePerHour: 60)
        check(slow.travelSpeed < medium.travelSpeed && medium.travelSpeed < fast.travelSpeed,
              "different measured rates must produce visibly ordered flight speed")
        check(slow.liftFraction == fast.liftFraction, "speed must never change quota altitude")
        check(RoadsterFlightState(remainingPercent: 60, ratePerHour: 0).travelSpeed == 0,
              "observed zero must stop the scenery")
        check(RoadsterFlightState(remainingPercent: 0, ratePerHour: 60).travelSpeed == 0,
              "exhaustion grounds the vehicle regardless of earlier speed")
        check(RoadsterFlightState(remainingPercent: 60, stale: true, ratePerHour: 60).travelSpeed == 0,
              "stale observations must not animate")
        let start = RoadsterLaunchPose(progress: 0, roll: true)
        let finish = RoadsterLaunchPose(progress: 1, roll: true)
        check(start.liftProgress == 0 && finish.liftProgress == 1,
              "launch starts at the old observed altitude and ends at the new one")
        check(abs(finish.rollDegrees - 360) < 0.001 && abs(finish.pitchDegrees) < 0.001 && abs(finish.yawDegrees) < 0.001 && finish.thrust < 0.001,
              "one rotation must end level, full size and without lingering launch thrust")
        var previous = 0.0
        for step in 0...100 {
            let pose = RoadsterLaunchPose(progress: Double(step) / 100, roll: true)
            check(pose.liftProgress >= previous && pose.liftProgress <= 1, "refill height curve must not overshoot")
            check(pose.pitchDegrees >= 0 && pose.pitchDegrees <= 19, "pitch remains bounded")
            check(pose.yawDegrees >= 0 && pose.yawDegrees <= 16, "yaw remains bounded")
            previous = pose.liftProgress
        }
        check(RoadsterLaunchPose(progress: 0.55, roll: true).rollDegrees > 100,
              "refill roll must have a visible inverted intermediate pose")
        check(RoadsterLaunchPose(progress: 0.55, roll: false).rollDegrees == 0,
              "small corrections should lift gently without a full roll")
        print("PASS: quota-to-altitude mapping, unknown/stale states, and visual bounds")
    }
}
