import json
from dataclasses import asdict
import math
from pathlib import Path
import struct
import sys
import time
import unittest
from unittest.mock import Mock

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'host'))
from protocol import Config, Stream, command, crc, decode_status, decode_imu_diagnostics
from server import Session


def frame(m2=True):
    raw = bytearray(46)
    raw[:3] = b'\xcb\xbc\x01'
    struct.pack_into('<BBBHHH', raw, 3, 9, 90 | (128 if m2 else 0), 3, 0, 60000, 60000)
    struct.pack_into('<hhii4hHHhBB3H', raw, 12, 250, -325, -123, 456, 10, -20, 30, -40, 7, 8, 50, 4, 0, 998, 3, 0)
    return bytes(raw) + struct.pack('<H', crc(raw))


class CodecTests(unittest.TestCase):
    def test_diagnostics_are_separate_from_control_status(self):
        raw=bytearray(46);raw[:8]=bytes((0xcb,0xbd,1,1,0x47,0x26,0x69,0))
        struct.pack_into('<II4H6hIIH',raw,8,123,4000,7,2,0,1000,0,4096,-8192,33,-66,99,9999,5999,0)
        packet=bytes(raw)+struct.pack('<H',crc(raw))
        diag=decode_imu_diagnostics(packet)
        self.assertEqual(diag['_type'],'imu_diagnostics');self.assertEqual(diag['who_am_i'],0x47)
        self.assertEqual(diag['az_g'],-1);self.assertEqual(diag['sda_low_permille'],1000)
        stream=Stream();rows=stream.feed(packet+frame()+packet)
        self.assertEqual(len(rows),3);self.assertNotIn('_type',rows[1]);self.assertEqual(stream.bad_crc,0)

    def test_separate_protocol_crc_and_length(self):
        packet = command('config', 255, Config(mode=3, axis=3, angle_kp=20).payload())
        self.assertEqual(len(packet), 48)
        self.assertEqual(packet[:6], b'\xb6\x6b\x01\x02\xff\x00')
        self.assertEqual(struct.unpack_from('<H', packet, 12)[0], 5120)
        self.assertEqual(crc(packet[:46]), int.from_bytes(packet[46:], 'little'))

    def test_motor_profiles_do_not_reuse_old_cpr(self):
        profiles = json.loads((ROOT / 'config/motors.json').read_text())['profiles']
        self.assertEqual(profiles['p30_gmr']['left_cpr'], 30 * 500 * 4)
        self.assertEqual(profiles['p30_hall']['left_cpr'], 30 * 13 * 4)
        self.assertFalse(profiles['p30_gmr']['measured'])

    def test_mode_axis_and_duration_policies(self):
        for kwargs in (dict(mode=1), dict(mode=2, axis=3, duration_ms=100),
                       dict(mode=3, axis=1), dict(mode=4, axis=3, duration_ms=100),
                       dict(fall_deg=3, start_deg=5)):
            with self.subTest(kwargs=kwargs), self.assertRaises(ValueError): Config(**kwargs).payload()
        for mode in (1, 2): self.assertEqual(len(Config(mode=mode, axis=1, duration_ms=100).payload()), 40)
        for mode in (3, 4): self.assertEqual(len(Config(mode=mode, axis=3).payload()), 40)

    def test_nonfinite_and_out_of_range_config(self):
        for kwargs in (dict(angle_kp=math.nan), dict(speed_ki=math.inf), dict(flags=32),
                       dict(pwm_limit=301), dict(wheel_kp_q8=0), dict(mode=True), dict(filter_shift=0)):
            with self.subTest(kwargs=kwargs), self.assertRaises(ValueError): Config(**kwargs).payload()

    def test_one_wheel_target_and_gmr_rpm_conversion(self):
        self.assertEqual(struct.unpack('<hhh', Config(mode=2, axis=1, duration_ms=100).target(1, 60000, 60000)), (10, 0, 0))
        self.assertEqual(struct.unpack('<hhh', Config(mode=2, axis=2, duration_ms=100).target(-1, 60000, 60000)), (0, -10, 0))
        self.assertEqual(struct.unpack('<hhh', Config(mode=1, axis=2, duration_ms=100).target(-30, 60000, 60000)), (0, -30, 0))
        with self.assertRaises(ValueError): Config(mode=1, axis=1, duration_ms=100).target(101, 60000, 60000)

    def test_outer_target_units_and_limits(self):
        self.assertEqual(struct.unpack('<hhh', Config(mode=4, axis=3).target(1, 60000, 60000)), (0, 0, 256))
        for value in (121, -121, math.nan, math.inf):
            with self.assertRaises(ValueError): Config(mode=4, axis=3).target(value, 60000, 60000)
        with self.assertRaises(ValueError): Config(mode=3, axis=3).target(1, 60000, 60000)

    def test_integral_time_quantization_exposed(self):
        result = Config(speed_ki=.1).to_dict()
        self.assertAlmostEqual(result['effective_speed_ki'], .1, delta=.0004)

    def test_status_signed_units_and_identity(self):
        data = decode_status(frame())
        self.assertEqual((data['pitch_deg'], data['rate_dps']), (2.5, -3.25))
        self.assertEqual((data['left_position'], data['right_position']), (-123, 456))
        self.assertEqual((data['left_rpm'], data['right_rpm']), (1, -2))
        self.assertTrue(data['drive_capable'])
        self.assertEqual(data['pin_profile'],'carrier_m2_23_30')
        self.assertEqual(decode_status(frame(m2=False))['pin_profile'],'legacy_distributed')
        self.assertFalse(data['armed'])
        self.assertEqual(data['config_sequence'], 4)

    def test_stream_fragmentation_corruption_and_other_firmware(self):
        data = frame()
        corrupted = bytearray(data); corrupted[24] ^= 1
        stream = Stream()
        self.assertEqual(stream.feed(b'\xc3\x3c\x01' + bytes(45) + corrupted + data[:19]), [])
        self.assertEqual(len(stream.feed(data[19:] + data)), 2)
        self.assertEqual(stream.bad_crc, 1)


class SessionTests(unittest.TestCase):
    def make_session(self):
        session = Session(live=True)
        session.closed.set(); session.thread.join(timeout=1)
        session.serial = Mock()
        session.serial.write = Mock()
        session.last = decode_status(frame())
        session.received = time.monotonic()
        self.addCleanup(session.disconnect)
        return session

    def test_demo_never_connects_or_arms(self):
        connector = Mock()
        session = Session(connector=connector)
        self.addCleanup(session.close)
        self.assertTrue(session.state()['demo'])
        with self.assertRaises(ValueError): session.connect('COM20')
        with self.assertRaises(ValueError): session.action({'action': 'arm'})
        connector.assert_not_called()

    def test_arm_requires_config_ack_and_matching_cpr(self):
        session = self.make_session()
        for config_seq, drive, cpr in ((None, True, 60000), (5, True, 60000), (4, False, 60000), (4, True, 1560)):
            session.config = Config(mode=1, axis=1, duration_ms=100)
            session.config_seq = config_seq
            session.last.update(drive_capable=drive, left_cpr=cpr)
            with self.assertRaises(ValueError): session.action({'action': 'arm', 'config': asdict(session.config)})
        session.serial.write.assert_not_called()

    def test_arm_rejects_unapplied_form_edits(self):
        session = self.make_session()
        session.config = Config(mode=3, axis=3)
        session.config_seq = 4
        edited = asdict(session.config); edited['angle_kp'] = 20
        with self.assertRaises(ValueError): session.action({'action': 'arm', 'config': edited})
        session.serial.write.assert_not_called()

    def test_arm_rejects_old_distributed_pin_firmware(self):
        session=self.make_session();session.last=decode_status(frame(m2=False))
        session.config=Config(mode=1,axis=1,duration_ms=100);session.config_seq=4
        with self.assertRaisesRegex(ValueError,'旧分散引脚'):
            session.action({'action':'arm','config':asdict(session.config)})
        session.serial.write.assert_not_called()

    def test_browser_timeout_sends_stop_and_never_restarts(self):
        session = self.make_session()
        session.intent = True; session.browser_hb = time.monotonic() - 1
        session.check_link(time.monotonic())
        self.assertFalse(session.intent)
        self.assertEqual(session.serial.write.call_args.args[0][3], 0)
        count = session.serial.write.call_count
        session.browser_hb = time.monotonic(); session.check_link(time.monotonic())
        self.assertEqual(session.serial.write.call_count, count)

    def test_stale_telemetry_stops_even_when_browser_alive(self):
        session = self.make_session()
        session.intent = True; session.browser_hb = time.monotonic(); session.received -= 1
        session.check_link(time.monotonic())
        self.assertFalse(session.intent)
        self.assertEqual(session.serial.write.call_args.args[0][3], 0)

    def test_running_config_rejected_before_write(self):
        session = self.make_session(); session.last['armed'] = True
        with self.assertRaises(ValueError): session.action({'action': 'config', 'config': {}})
        session.serial.write.assert_not_called()

    def test_unknown_fields_and_nan_rejected_before_write(self):
        session = self.make_session()
        for config in ({'angle_kp': math.nan}, {'foc_kp': 4096}):
            with self.assertRaises(ValueError): session.action({'action': 'config', 'config': config})
        session.serial.write.assert_not_called()


if __name__ == '__main__': unittest.main()
