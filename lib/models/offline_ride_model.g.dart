// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'offline_ride_model.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class OfflineRideModelAdapter extends TypeAdapter<OfflineRideModel> {
  @override
  final int typeId = 0;

  @override
  OfflineRideModel read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return OfflineRideModel(
      id: fields[0] as String,
      passengerId: fields[1] as String,
      pickupLat: fields[2] as double,
      pickupLng: fields[3] as double,
      dropoffLat: fields[4] as double,
      dropoffLng: fields[5] as double,
      pickupAddress: fields[6] as String,
      dropoffAddress: fields[7] as String,
      fare: fields[8] as double,
      estimatedDuration: fields[9] as int,
      distance: fields[10] as double?,
      requestedAt: fields[11] as DateTime,
      notes: fields[12] as String?,
      barangayId: fields[13] as String?,
      barangayName: fields[14] as String?,
      passengerCount: fields[15] as int,
      isPasaBuy: fields[16] as bool,
      itemDescription: fields[17] as String?,
      status: fields[18] as String,
      createdAt: fields[19] as DateTime?,
      syncedAt: fields[20] as DateTime?,
      syncError: fields[21] as String?,
      firestoreRideId: fields[22] as String?,
      syncAttempts: fields[23] as int,
    );
  }

  @override
  void write(BinaryWriter writer, OfflineRideModel obj) {
    writer
      ..writeByte(24)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.passengerId)
      ..writeByte(2)
      ..write(obj.pickupLat)
      ..writeByte(3)
      ..write(obj.pickupLng)
      ..writeByte(4)
      ..write(obj.dropoffLat)
      ..writeByte(5)
      ..write(obj.dropoffLng)
      ..writeByte(6)
      ..write(obj.pickupAddress)
      ..writeByte(7)
      ..write(obj.dropoffAddress)
      ..writeByte(8)
      ..write(obj.fare)
      ..writeByte(9)
      ..write(obj.estimatedDuration)
      ..writeByte(10)
      ..write(obj.distance)
      ..writeByte(11)
      ..write(obj.requestedAt)
      ..writeByte(12)
      ..write(obj.notes)
      ..writeByte(13)
      ..write(obj.barangayId)
      ..writeByte(14)
      ..write(obj.barangayName)
      ..writeByte(15)
      ..write(obj.passengerCount)
      ..writeByte(16)
      ..write(obj.isPasaBuy)
      ..writeByte(17)
      ..write(obj.itemDescription)
      ..writeByte(18)
      ..write(obj.status)
      ..writeByte(19)
      ..write(obj.createdAt)
      ..writeByte(20)
      ..write(obj.syncedAt)
      ..writeByte(21)
      ..write(obj.syncError)
      ..writeByte(22)
      ..write(obj.firestoreRideId)
      ..writeByte(23)
      ..write(obj.syncAttempts);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is OfflineRideModelAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
