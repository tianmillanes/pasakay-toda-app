// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'offline_ride_history_model.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class OfflineRideHistoryModelAdapter
    extends TypeAdapter<OfflineRideHistoryModel> {
  @override
  final int typeId = 1;

  @override
  OfflineRideHistoryModel read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return OfflineRideHistoryModel(
      rideId: fields[0] as String,
      passengerId: fields[1] as String,
      driverId: fields[2] as String?,
      driverName: fields[3] as String?,
      pickupLat: fields[4] as double,
      pickupLng: fields[5] as double,
      dropoffLat: fields[6] as double,
      dropoffLng: fields[7] as double,
      pickupAddress: fields[8] as String,
      dropoffAddress: fields[9] as String,
      fare: fields[10] as double,
      status: fields[11] as String,
      requestedAt: fields[12] as DateTime,
      completedAt: fields[13] as DateTime?,
      barangayName: fields[14] as String?,
      passengerCount: fields[15] as int,
      rating: fields[16] as double?,
      notes: fields[17] as String?,
      syncedAt: fields[18] as DateTime?,
    );
  }

  @override
  void write(BinaryWriter writer, OfflineRideHistoryModel obj) {
    writer
      ..writeByte(19)
      ..writeByte(0)
      ..write(obj.rideId)
      ..writeByte(1)
      ..write(obj.passengerId)
      ..writeByte(2)
      ..write(obj.driverId)
      ..writeByte(3)
      ..write(obj.driverName)
      ..writeByte(4)
      ..write(obj.pickupLat)
      ..writeByte(5)
      ..write(obj.pickupLng)
      ..writeByte(6)
      ..write(obj.dropoffLat)
      ..writeByte(7)
      ..write(obj.dropoffLng)
      ..writeByte(8)
      ..write(obj.pickupAddress)
      ..writeByte(9)
      ..write(obj.dropoffAddress)
      ..writeByte(10)
      ..write(obj.fare)
      ..writeByte(11)
      ..write(obj.status)
      ..writeByte(12)
      ..write(obj.requestedAt)
      ..writeByte(13)
      ..write(obj.completedAt)
      ..writeByte(14)
      ..write(obj.barangayName)
      ..writeByte(15)
      ..write(obj.passengerCount)
      ..writeByte(16)
      ..write(obj.rating)
      ..writeByte(17)
      ..write(obj.notes)
      ..writeByte(18)
      ..write(obj.syncedAt);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is OfflineRideHistoryModelAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
