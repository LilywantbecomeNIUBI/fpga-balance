"""Balance V2 wire format. No serial I/O or side effects on import."""
import binascii
import math
import struct
from dataclasses import dataclass, asdict

COMMANDS = {'heartbeat': 0, 'stop': 1, 'clear': 2, 'current_zero': 3,
            'attitude_zero': 4, 'arm': 6, 'start': 7, 'config': 8,
            'commission_m1': 9, 'commission_m2': 10}
GATES = ['驱动版固件', 'IMU新鲜有效', '姿态已校零', '电流已校零', '双电机电角已标定',
         '姿态与前进轴向已确认', 'M1已验收', 'M2已验收', '处于启动角内', '主机心跳', '电机无故障', '停止锁存已解除']

# Vehicle installation confirmed 2026-10-27; not a runtime preference.
IMU_ORIENTATION_FLAGS = 0b011  # Y axis, reversed pitch (front positive), upright -Z.


def crc(data):
    return binascii.crc_hqx(data, 0xffff)


def frame(body):
    if len(body) != 32:
        raise ValueError('body must be 32 bytes')
    return b'@' + body.hex().upper().encode() + b'*' + f'{crc(body):04X}\n'.encode()


def command(name, seq):
    return frame(bytes([2, seq & 255, COMMANDS[name]]) + bytes(29))


@dataclass
class Config:
    m1_reverse: bool = False
    m2_reverse: bool = True
    axis_confirmed: bool = False
    m1_accepted: bool = False
    m2_accepted: bool = False
    kp: float = 0.0
    kd: float = 0.0
    foc_kp: int = 16384
    foc_ki: int = 256
    trim_deg: float = 0.0
    current_ma: int = 100
    cutoff_deg: float = 15.0
    start_deg: float = 3.0
    duration_ms: int = 1000
    filter_shift: int = 8

    mode: int = 0
    test_axis: int = 1
    current_target_ma: int = 0
    speed_target_rpm: float = 0.0
    speed_kp: float = 0.0
    speed_ki: float = 0.0

    def body(self, seq):
        bounds = [('kp', 0, .5), ('kd', 0, .1), ('foc_kp', 0, 16384), ('foc_ki', 0, 256),
                  ('trim_deg', -5, 5), ('current_ma', 1, 1000), ('cutoff_deg', 5, 15),
                  ('start_deg', .01, 5), ('duration_ms', 100, 5000), ('filter_shift', 4, 10)]
        for name, lo, hi in bounds:
            v = getattr(self, name)
            if isinstance(v, bool) or not isinstance(v, (int, float)) or not math.isfinite(v) or not lo <= v <= hi:
                raise ValueError(f'{name}: {lo}..{hi}')
        for name in ('foc_kp', 'foc_ki', 'current_ma', 'duration_ms', 'filter_shift'):
            if int(getattr(self, name)) != getattr(self, name):
                raise ValueError(f'{name} must be integer')
        # Wire bit5 acknowledges measured IMU and wheel-forward axes. Torque
        # correction signs are separate m1_reverse/m2_reverse settings to test.
        keys = ['m1_reverse', 'm2_reverse', 'axis_confirmed', 'm1_accepted', 'm2_accepted']
        if any(type(getattr(self, k)) is not bool for k in keys):
            raise ValueError('confirmation and direction fields must be boolean')
        if round(self.start_deg * 100) >= round(self.cutoff_deg * 100):
            raise ValueError('start angle must be below cutoff')
        flags = IMU_ORIENTATION_FLAGS | sum(int(getattr(self, k)) << (i+3) for i, k in enumerate(keys))
        if self.mode not in (0,1,2) or type(self.mode) is not int: raise ValueError('mode: 0/1/2')
        if self.test_axis not in (1,2,3) or type(self.test_axis) is not int: raise ValueError('test_axis: 1/2/3')
        if type(self.current_target_ma) is not int or abs(self.current_target_ma)>self.current_ma: raise ValueError('current target exceeds current limit')
        for k,hi in [('speed_target_rpm',60),('speed_kp',.255),('speed_ki',.255)]:
            v=getattr(self,k)
            if isinstance(v,bool) or not isinstance(v,(float,int)) or not math.isfinite(v) or (abs(v)>hi if k=='speed_target_rpm' else not 0<=v<=hi):raise ValueError(k)
        # Vehicle forward speed: right M1 inverted, left M2 normal (fixed bits01).
        packed_mode=self.mode | 4 | (self.test_axis<<4)
        target=self.current_target_ma if self.mode==1 else round(self.speed_target_rpm*10) if self.mode==2 else 0
        return struct.pack('<BBBBIIHHhHHHHBBhBB', 2, seq & 255, 8, flags,
                           round(self.kp * 2**24), round(self.kd * 2**24), self.foc_kp, self.foc_ki,
                           round(self.trim_deg * 100), self.current_ma, round(self.cutoff_deg * 100),
                           round(self.start_deg * 100), self.duration_ms, self.filter_shift, packed_mode, target, round(self.speed_kp*1000), round(self.speed_ki*1000))


class Parser:
    def __init__(self):
        self.buffer = bytearray()
        self.crc_errors = self.discarded = self.packets = self.gaps = 0
        self.last_imu_seq = None

    def feed(self, data):
        self.buffer.extend(data)
        records = []
        while len(self.buffer) >= 4:
            payload = self.buffer[3]
            if self.buffer[:3] != b'\xa5\xb6\x02' or payload not in (128,168):
                self.buffer.pop(0); self.discarded += 1; continue
            size = payload+1
            if len(self.buffer)<size:break
            p = bytes(self.buffer[:size])
            if crc(p[:payload-2]) != int.from_bytes(p[payload-2:payload], 'little') or self._xor(p[:payload]) != p[payload]:
                self.crc_errors += 1; self.buffer.pop(0); continue
            del self.buffer[:size]
            r = decode(p)
            if self.last_imu_seq is not None:
                delta = (r['imu_seq'] - self.last_imu_seq) & 0xffffffff
                # Normal decimation is ~5 samples. Count unusually large gaps, not skipped 1 kHz samples.
                if 20 < delta < 0x80000000: self.gaps += 1
            self.last_imu_seq = r['imu_seq']; self.packets += 1
            records.append(r)
        return records

    @staticmethod
    def _xor(data):
        value = 0
        for b in data: value ^= b
        return value


def decode(p):
    u16 = lambda o: struct.unpack_from('<H', p, o)[0]
    i16 = lambda o: struct.unpack_from('<h', p, o)[0]
    u32 = lambda o: struct.unpack_from('<I', p, o)[0]
    i32 = lambda o: struct.unpack_from('<i', p, o)[0]
    a, b = p[16:18]
    record = dict(time_us=u32(4), imu_seq=u32(8), motor_seq=u32(12), drive=bool(a & 1),
                attitude_calibrated=bool(a & 2), attitude_calibrating=bool(a & 4),
                current_calibrated=bool(a & 8), current_calibrating=bool(a & 16),
                running=bool(a & 32), commissioning=bool(a & 64), commission_failed=bool(a & 128),
                active=bool(b & 1), armed=bool(b & 2), estop=bool(b & 4), attitude_bad=bool(b & 8),
                independent_commission=bool(b & 64), preserve_commission_on_clear=bool(b & 128), commission_axis=(p[85]>>2)&3,
                imu_ok=bool(b & 16), configured=bool(b & 32), gates=u16(18), stop_reason=u16(20),
                motor_faults=u16(22), pitch=i32(24)/65536, rate=i32(28)/65536,
                shadow_a=i16(32)/4096, iq1_a=i16(34)/4096, iq2_a=i16(36)/4096,
                interval_us=u16(38), age_us=u32(40), accel=[i16(o)/8192 for o in (44,46,48)],
                gyro=[i16(o)*1000/32768 for o in (50,52,54)], temp_c=i16(56)/132.48+25,
                currents_a=[i16(o)/4096 for o in range(58,70,2)], angles=[u16(70),u16(72)],
                zero_progress=u16(74), imu_errors=u16(76), imu_invalid=u16(78), rx_errors=u16(80),
                ack_seq=p[82], result=p[83], rejected=p[84], commissioned_mask=p[85]&3,
                commission_state=p[85]>>4, who_am_i=p[86], imu_last_error=p[87], config_hex=p[88:120].hex(), wheel_rpm=[i16(120)/10,i16(122)/10], speed_trim_deg=i16(124)/100)
    record['m2_diagnostic']=None
    if len(p)==169 and p[165]==0xd2:
        t=126
        record['m2_diagnostic']=dict(sequence=u32(t),sample_time=u32(t+4),mechanical=u16(t+8),theta=u16(t+10),
            currents_a=[i16(t+k)/4096 for k in (12,14,16)],id_ref_a=i16(t+18)/4096,iq_ref_a=i16(t+20)/4096,
            running=bool(p[t+22]&1),alignment=bool(p[t+22]&2),id_a=i16(t+23)/4096,iq_a=i16(t+25)/4096,
            ud=i16(t+27)/32768,uq=i16(t+29)/32768,park_valid=bool(p[t+31]&1),overrun=bool(p[t+31]&2),
            learned_zero=[u16(158),u16(160)],learned_reverse=p[162]&3,selected_motor=p[163],simple_protection=bool(p[164]&1))
    return record



def demo_packet(t=0.0):
    """Observation-only simulated telemetry; never opens a serial port."""
    p = bytearray(128)
    p[:4] = b'\xa5\xb6\x02\x80'
    struct.pack_into('<III', p, 4, int(t*1e6)&0xffffffff, int(t*1000)&0xffffffff, int(t*20000)&0xffffffff)
    p[16], p[17], p[86] = 2, 80, 0x47
    struct.pack_into('<ii', p, 24, int(math.sin(t)*4*65536), int(math.cos(t)*4*65536))
    struct.pack_into('<HI', p, 38, 1000, 200)
    struct.pack_into('<hhh', p, 44, 0, 0, -8192)
    struct.pack_into('<H', p, 126, crc(p[:126]))
    return bytes(p)+bytes([Parser._xor(p)])
