"""Brushed balance v1 codec. Pure functions; importing never opens hardware."""
import binascii
import math
import struct
from dataclasses import asdict, dataclass

COMMANDS = {'stop': 0, 'clear': 1, 'config': 2, 'zero': 3, 'arm': 4, 'target': 5, 'heartbeat': 6}
FAULTS = {1: '上电/STOP锁存', 2: '主机心跳超时', 4: 'IMU/姿态过期', 8: '倾倒',
          16: 'AB非法跳变过多', 32: '编码器超速', 64: '有输出但无编码器运动'}


def crc(data):
    return binascii.crc_hqx(data, 0xffff)


def command(name, seq, payload=b''):
    if name not in COMMANDS or len(payload) > 40:
        raise ValueError('Unknown command or oversized payload')
    body = b'\xb6\x6b' + bytes((1, COMMANDS[name], seq & 255, 0)) + payload.ljust(40, b'\0')
    return body + struct.pack('<H', crc(body))


def integer(value, low, high, name):
    if isinstance(value, bool) or not isinstance(value, int) or not low <= value <= high:
        raise ValueError(f'{name}: expected integer {low}..{high}')
    return value


@dataclass
class Config:
    mode: int = 0
    flags: int = 0
    axis: int = 0
    filter_shift: int = 6
    pwm_limit: int = 100
    angle_kp: float = 0.0
    angle_kd: float = 0.0
    wheel_kp_q8: int = 256
    wheel_ki_q8: int = 0
    speed_kp: float = 0.0
    speed_ki: float = 0.0
    trim_deg: float = 0.0
    start_deg: float = 5.0
    fall_deg: float = 35.0
    speed_trim_deg: float = 3.0
    duration_ms: int = 0

    def payload(self):
        for name, lo, hi in [('mode', 0, 4), ('flags', 0, 31), ('axis', 0, 3),
                             ('filter_shift', 2, 10), ('pwm_limit', 1, 300),
                             ('wheel_kp_q8', 1, 4096), ('wheel_ki_q8', 0, 1024),
                             ('duration_ms', 0, 5000)]:
            integer(getattr(self, name), lo, hi, name)
        for name, lo, hi in [('angle_kp', 0, 100), ('angle_kd', 0, 20), ('speed_kp', 0, .5),
                             ('speed_ki', 0, 1), ('trim_deg', -5, 5), ('start_deg', 1, 10),
                             ('fall_deg', 1, 60), ('speed_trim_deg', 0, 6)]:
            v = getattr(self, name)
            if isinstance(v, bool) or not isinstance(v, (float, int)) or not math.isfinite(v) or not lo <= v <= hi:
                raise ValueError(f'{name}: expected finite value {lo}..{hi}')
        if round(self.fall_deg * 100) <= round(self.start_deg * 100):
            raise ValueError('Fall angle must exceed start angle')
        if self.mode == 0 and (self.axis != 0 or self.duration_ms != 0):
            raise ValueError('Observe requires axis=0, duration=0')
        if self.mode in (1, 2) and (self.axis not in (1, 2) or not 100 <= self.duration_ms <= 5000):
            raise ValueError('Bench mode requires one wheel and duration 100..5000ms')
        if self.mode in (3, 4) and (self.axis != 3 or self.duration_ms != 0):
            raise ValueError('Balance requires both wheels and duration=0')
        return struct.pack('<BBBB7Hh4H12x', self.mode, self.flags, self.axis, self.filter_shift,
                           self.pwm_limit, round(self.angle_kp * 256), round(self.angle_kd * 256),
                           self.wheel_kp_q8, self.wheel_ki_q8, round(self.speed_kp * 65536),
                           round(self.speed_ki * 65536 / 50), round(self.trim_deg * 100),
                           round(self.start_deg * 100), round(self.fall_deg * 100),
                           round(self.speed_trim_deg * 100), self.duration_ms)

    def target(self, value, left_cpr, right_cpr):
        if not isinstance(value, (float, int)) or isinstance(value, bool) or not math.isfinite(value):
            raise ValueError('Target must be finite')
        left = right = rpm = 0
        if self.mode == 1:
            if value != round(value) or abs(value) > self.pwm_limit:
                raise ValueError('PWM target exceeds configured limit')
            if self.axis == 1: left = int(value)
            else: right = int(value)
        elif self.mode == 2:
            if abs(value) > 120:
                raise ValueError('Bench speed target must be within +/-120 rpm')
            counts = round(value * (left_cpr if self.axis == 1 else right_cpr) / 6000)
            if abs(counts) > 4096:
                raise ValueError('Target exceeds encoder command range')
            if self.axis == 1: left = counts
            else: right = counts
        elif self.mode == 4:
            if abs(value) > 120:
                raise ValueError('Speed target must be within +/-120 rpm')
            rpm = round(value * 256)
        elif value != 0:
            raise ValueError('This mode accepts only zero speed target')
        return struct.pack('<hhh', left, right, rpm)

    def to_dict(self):
        result = asdict(self)
        result['effective_speed_ki'] = round(self.speed_ki * 65536 / 50) * 50 / 65536
        return result


def decode_status(frame):
    if len(frame) != 48 or frame[:3] != b'\xcb\xbc\x01' or crc(frame[:46]) != struct.unpack_from('<H', frame, 46)[0]:
        raise ValueError('Not a valid brushed-balance v1 frame')
    seq, flags, mode, faults, cpr_l, cpr_r = struct.unpack_from('<BBBHHH', frame, 3)
    pitch, rate, lp, rp, lv, rv, la, ra, li, ri, trim, ack, reason, interval, rejected, packet = struct.unpack_from('<hhii4hHHhBB3H', frame, 12)
    return dict(last_sequence=seq, armed=bool(flags & 1), calibrated=bool(flags & 2),
                calibrating=bool(flags & 4), config_valid=bool(flags & 8), imu_healthy=bool(flags & 16),
                drive_capable=bool(flags & 64), pin_profile='carrier_m2_23_30' if flags & 128 else 'legacy_distributed', mode=mode, faults=faults,
                fault_names=[name for mask, name in FAULTS.items() if faults & mask],
                left_cpr=cpr_l, right_cpr=cpr_r, pitch_deg=pitch / 100, rate_dps=rate / 100,
                left_position=lp, right_position=rp, left_velocity=lv, right_velocity=rv,
                left_rpm=lv * 6000 / cpr_l if cpr_l else None,
                right_rpm=rv * 6000 / cpr_r if cpr_r else None,
                left_pwm=la, right_pwm=ra, left_invalid=li, right_invalid=ri,
                speed_trim_deg=trim / 100, config_sequence=ack, stop_reason=reason,
                interval_us=interval, rejected=rejected, packet_count=packet)


IMU_ERRORS = {0: '无错误/初始化中', 1: 'I2C未收到应答（NACK）', 2: 'I2C总线超时',
              0x10: 'WHO_AM_I不匹配', 0x11: '配置寄存器回读不匹配',
              0x12: '启动状态检查失败', 0x13: '有效样本超时', 0x1f: '采集状态异常'}


def decode_imu_diagnostics(frame):
    if len(frame) != 48 or frame[:3] != b'\xcb\xbd\x01' or crc(frame[:46]) != struct.unpack_from('<H', frame, 46)[0]:
        raise ValueError('Invalid IMU diagnostics')
    error, who, flags, address = frame[3:7]
    seq, age, errors, invalids, scl_low, sda_low, ax, ay, az, gx, gy, gz, now, commit, packet = struct.unpack_from('<II4H6hIIH', frame, 8)
    return dict(_type='imu_diagnostics', last_error=error, error_text=IMU_ERRORS.get(error, '未知错误'),
                who_am_i=who, address=address, ready=bool(flags & 1), fault=bool(flags & 2), stale=bool(flags & 4),
                scl_high=bool(flags & 32), sda_high=bool(flags & 16), sample_seq=seq, sample_age_us=age,
                error_count=errors, invalid_count=invalids, scl_low_permille=scl_low, sda_low_permille=sda_low,
                ax_g=ax/8192, ay_g=ay/8192, az_g=az/8192, gx_dps=gx*1000/32768,
                gy_dps=gy*1000/32768, gz_dps=gz*1000/32768, now_us=now, commit_us=commit, packet_count=packet)


class Stream:
    def __init__(self):
        self.buffer = bytearray()
        self.bad_crc = 0

    def feed(self, data):
        self.buffer.extend(data)
        result = []
        while len(self.buffer) >= 2:
            candidates = [i for i in (self.buffer.find(b'\xcb\xbc'), self.buffer.find(b'\xcb\xbd')) if i >= 0]
            if not candidates:
                self.buffer[:] = self.buffer[-1:]
                break
            index = min(candidates)
            del self.buffer[:index]
            if len(self.buffer) < 48: break
            try:
                decoder = decode_imu_diagnostics if self.buffer[1] == 0xbd else decode_status
                result.append(decoder(bytes(self.buffer[:48])))
            except ValueError:
                self.bad_crc += 1
                del self.buffer[0]
                continue
            del self.buffer[:48]
        return result
