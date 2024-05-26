import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:panda_sync/src/services/connectivity_service.dart';
import 'package:panda_sync/src/services/local_storage_service.dart';
import 'package:panda_sync/src/services/synchronization_service.dart';
import 'package:panda_sync/src/utils/isar_manager.dart';

import '../panda_sync.dart';

class OfflineFirstClient {
  static final OfflineFirstClient _instance =
      OfflineFirstClient._createInstance();
  final Dio dio;
  final LocalStorageService localStorage;
  final ConnectivityService connectivityService;
  final SynchronizationService synchronizationService;

  factory OfflineFirstClient() => _instance;

  OfflineFirstClient._(this.dio, this.localStorage, this.connectivityService,
      this.synchronizationService) {
    connectivityService.connectivityStream.listen(handleConnectivityChange);
  }

  @visibleForTesting
  OfflineFirstClient.createForTest(this.dio, this.localStorage,
      this.connectivityService, this.synchronizationService);

  static OfflineFirstClient _createInstance() {
    Dio dio = Dio(); // Optionally configure Dio here
    LocalStorageService localStorage =
        LocalStorageService(IsarManager.getIsarInstance());
    ConnectivityService connectivityService = ConnectivityService();
    SynchronizationService synchronizationService =
        SynchronizationService(localStorage);

    return OfflineFirstClient._(
        dio, localStorage, connectivityService, synchronizationService);
  }

  Future<Response<T>> get<T extends Identifiable>(String url,
      {Map<String, dynamic>? queryParameters}) async {
    var registryEntry = TypeRegistry.get<T>();
    if (registryEntry == null) {
      throw Exception("Type ${T.toString()} is not registered.");
    }

    if (await connectivityService.isConnected()) {
      try {
        Response<dynamic> response =
            await dio.get(url, queryParameters: queryParameters);
        T result = registryEntry.fromJson(response.data);
        await localStorage.storeData<T>(result);
        return _dioResponse<T>(result, response);
      } catch (e) {
        return await fetchFromLocalStorage<T>(url);
      }
    } else {
      return await fetchFromLocalStorage<T>(url);
    }
  }

  Future<Response<T>> post<T extends Identifiable>(String url, T data,
      {Map<String, dynamic>? queryParameters}) async {
    var registryEntry = TypeRegistry.get<T>();
    if (registryEntry == null) {
      throw Exception("Type ${T.toString()} is not registered.");
    }

    if (await connectivityService.isConnected()) {
      try {
        Response<dynamic> response = await dio.post(url,
            data: registryEntry.toJson(data), queryParameters: queryParameters);
        T result = registryEntry.fromJson(response.data);
        await localStorage.storeData<T>(data);
        return _dioResponse<T>(result, response);
      } catch (e) {
        await localStorage.storeRequest(url, 'POST', queryParameters, data);
        await localStorage.updateCachedData<T>(data);
        return Response<T>(
          requestOptions: RequestOptions(path: url),
          statusCode: 206,
          statusMessage: e.toString(),
        );
      }
    } else {
      await localStorage.storeRequest(url, 'POST', queryParameters, data);
      await localStorage.updateCachedData<T>(data);
      return Response<T>(
        requestOptions: RequestOptions(path: url),
        statusCode: 206,
        statusMessage: 'No connectivity',
      );
    }
  }

  Future<Response<T>> put<T extends Identifiable>(String url, T data,
      {Map<String, dynamic>? queryParameters}) async {
    var registryEntry = TypeRegistry.get<T>();
    if (registryEntry == null) {
      throw Exception("Type ${T.toString()} is not registered.");
    }

    if (await connectivityService.isConnected()) {
      try {
        Response<dynamic> response = await dio.put(url,
            data: registryEntry.toJson(data), queryParameters: queryParameters);
        await localStorage.updateCachedData<T>(data);
        T result = registryEntry.fromJson(response.data);
        return _dioResponse<T>(result, response);
      } catch (e) {
        await localStorage.storeRequest(url, 'PUT', queryParameters, data);
        await localStorage.updateCachedData<T>(data);
        return Response<T>(
          data: data,
          requestOptions: RequestOptions(path: url),
          statusCode: 206,
          statusMessage: e.toString(),
        );
      }
    } else {
      await localStorage.storeRequest(url, 'PUT', queryParameters, data);
      await localStorage.updateCachedData<T>(data);
      return Response<T>(
        data: data,
        requestOptions: RequestOptions(path: url),
        statusCode: 206,
        statusMessage: 'No connectivity',
      );
    }
  }

  Future<Response<T>> delete<T extends Identifiable>(String url, T data,
      {Map<String, dynamic>? queryParameters}) async {
    var registryEntry = TypeRegistry.get<T>();
    if (registryEntry == null) {
      throw Exception("Type ${T.toString()} is not registered.");
    }

    if (await connectivityService.isConnected()) {
      try {
        Response<dynamic> response = await dio.delete(url,
            data: registryEntry.toJson(data), queryParameters: queryParameters);
        T result = registryEntry.fromJson(response.data);
        await localStorage.removeData<T>(data.id);
        return _dioResponse<T>(result, response);
      } catch (e) {
        await localStorage.storeRequest(url, 'DELETE', queryParameters, data);
        await localStorage.updateCachedData<T>(data);
        return Response<T>(
          data: data,
          requestOptions: RequestOptions(path: url),
          statusCode: 206,
          statusMessage: e.toString(),
        );
      }
    } else {
      await localStorage.storeRequest(url, 'DELETE', queryParameters, data);
      await localStorage.updateCachedData<T>(data);
      return Response<T>(
        requestOptions: RequestOptions(path: url),
        statusCode: 206,
        statusMessage: 'No connectivity',
      );
    }
  }

  @visibleForTesting
  Future<Response<T>> fetchFromLocalStorage<T extends Identifiable>(
      String url) async {
    var registryEntry = TypeRegistry.get<T>();
    if (registryEntry == null) {
      throw Exception("Type ${T.toString()} is not registered.");
    }

    List<T> cachedData = await localStorage.getData<T>();
    if (cachedData.isNotEmpty) {
      return Response<T>(
        data: cachedData.first,
        statusCode: 206,
        requestOptions: RequestOptions(path: url),
      );
    } else {
      return Response<T>(
        statusCode: 206,
        statusMessage: 'No data available',
        requestOptions: RequestOptions(path: url),
      );
    }
  }

  Future<Response<List<T>>> getList<T extends Identifiable>(String url,
      {Map<String, dynamic>? queryParameters}) async {
    var registryEntry = TypeRegistry.get<T>();
    if (registryEntry == null) {
      throw Exception("Type ${T.toString()} is not registered.");
    }

    if (await connectivityService.isConnected()) {
      try {
        Response<dynamic> response =
            await dio.get(url, queryParameters: queryParameters);
        List<T> resultList = (response.data as List)
            .map((item) => registryEntry.fromJson(item) as T)
            .toList();
        await localStorage.storeDataList<T>(resultList);
        return _dioResponse<List<T>>(resultList, response);
      } catch (e) {
        return await fetchListFromLocalStorage<T>(url);
      }
    } else {
      return await fetchListFromLocalStorage<T>(url);
    }
  }

  Future<Response<List<T>>> postList<T extends Identifiable>(
      String url, List<T> dataList,
      {Map<String, dynamic>? queryParameters}) async {
    var registryEntry = TypeRegistry.get<T>();
    if (registryEntry == null) {
      throw Exception("Type ${T.toString()} is not registered.");
    }

    List<Response<T>> responses = [];
    if (await connectivityService.isConnected()) {
      for (var data in dataList) {
        try {
          Response<dynamic> response = await dio.post(url,
              data: registryEntry.toJson(data),
              queryParameters: queryParameters);
          if (response.data != null) {
            responses.addAll(response.data
                .map((item) => registryEntry.fromJson(item) as T)
                .map((e) => _dioResponse<T>(e, response))
                .toList());
          }
          await localStorage.storeData<T>(data);
        } catch (e) {
          responses.add(Response<T>(
            requestOptions: RequestOptions(path: url),
            statusCode: 206,
            statusMessage: e.toString(),
          ));
          await localStorage.storeRequest(url, 'POST', queryParameters, data);
        }
      }
    } else {
      for (var data in dataList) {
        responses.add(Response<T>(
          requestOptions: RequestOptions(path: url),
          statusCode: 206,
          statusMessage: 'No connectivity, operation queued',
        ));
        await localStorage.storeRequest(url, 'POST', queryParameters, data);
        await localStorage.storeData<T>(data);
      }
    }
    return Response<List<T>>(
      data: responses
          .where((response) => response.data != null)
          .map((response) => response.data!)
          .toList(),
      statusCode: responses.any((r) => r.statusCode != 200) ? 206 : 200,
      requestOptions: RequestOptions(path: url),
    );
  }

  Future<Response<List<T>>> putList<T extends Identifiable>(
      String url, List<T> dataList,
      {Map<String, dynamic>? queryParameters}) async {
    var registryEntry = TypeRegistry.get<T>();
    if (registryEntry == null) {
      throw Exception("Type ${T.toString()} is not registered.");
    }

    List<Response<T>> responses = [];
    if (await connectivityService.isConnected()) {
      for (var data in dataList) {
        try {
          Response<dynamic> response = await dio.put(url,
              data: registryEntry.toJson(data),
              queryParameters: queryParameters);
          if (response.data != null) {
            responses.addAll(response.data
                .map((item) => registryEntry.fromJson(item) as T)
                .map((e) => _dioResponse<T>(e, response))
                .toList());
          }
          await localStorage.updateCachedData<T>(data);
        } catch (e) {
          responses.add(Response<T>(
            requestOptions: RequestOptions(path: url),
            statusCode: 206,
            statusMessage: e.toString(),
          ));
          await localStorage.storeRequest(url, 'PUT', queryParameters, data);
          await localStorage.updateCachedData<T>(data);
        }
      }
    } else {
      for (var data in dataList) {
        responses.add(Response<T>(
          requestOptions: RequestOptions(path: url),
          statusCode: 206,
          statusMessage: 'No connectivity, operation queued',
        ));
        await localStorage.storeRequest(url, 'PUT', queryParameters, data);
        await localStorage.updateCachedData<T>(data);
      }
    }
    return Response<List<T>>(
      data: responses
          .where((response) => response.data != null)
          .map((response) => response.data!)
          .toList(),
      statusCode: responses.any((r) => r.statusCode != 200) ? 206 : 200,
      requestOptions: RequestOptions(path: url),
    );
  }

  Future<Response<List<T>>> deleteList<T extends Identifiable>(
      String url, List<T> dataList,
      {Map<String, dynamic>? queryParameters}) async {
    var registryEntry = TypeRegistry.get<T>();
    if (registryEntry == null) {
      throw Exception("Type ${T.toString()} is not registered.");
    }

    List<Response<T>> responses = [];
    if (await connectivityService.isConnected()) {
      for (var data in dataList) {
        try {
          Response<dynamic> response = await dio.delete(url,
              data: registryEntry.toJson(data),
              queryParameters: queryParameters);
          if (response.data != null) {
            responses.addAll(response.data
                .map((item) => registryEntry.fromJson(item) as T)
                .map((e) => _dioResponse<T>(e, response))
                .toList());
          }
          await localStorage.removeData<T>(data.id);
        } catch (e) {
          responses.add(Response<T>(
            requestOptions: RequestOptions(path: url),
            statusCode: 206,
            statusMessage: e.toString(),
          ));
          await localStorage.storeRequest(url, 'DELETE', queryParameters, data);
          await localStorage.removeData<T>(data.id);
        }
      }
    } else {
      for (var data in dataList) {
        responses.add(Response<T>(
          requestOptions: RequestOptions(path: url),
          statusCode: 206,
          statusMessage: 'No connectivity, operation queued',
        ));
        await localStorage.storeRequest(url, 'DELETE', queryParameters, data);
        await localStorage.removeData<T>(data.id);
      }
    }
    return Response<List<T>>(
      data: responses
          .where((response) => response.data != null)
          .map((response) => response.data!)
          .toList(),
      statusCode: responses.any((r) => r.statusCode != 200) ? 206 : 200,
      requestOptions: RequestOptions(path: url),
    );
  }

  @visibleForTesting
  Future<Response<List<T>>> fetchListFromLocalStorage<T extends Identifiable>(
      String url) async {
    var registryEntry = TypeRegistry.get<T>();
    if (registryEntry == null) {
      throw Exception("Type ${T.toString()} is not registered.");
    }

    List<T> cachedData = await localStorage.getData<T>();
    if (cachedData.isNotEmpty) {
      return Response<List<T>>(
        data: cachedData,
        statusCode: 200,
        requestOptions: RequestOptions(path: url),
      );
    } else {
      return Response<List<T>>(
        data: [],
        statusCode: 206,
        statusMessage: 'No data available',
        requestOptions: RequestOptions(path: url),
      );
    }
  }

  @visibleForTesting
  void handleConnectivityChange(bool isConnected) {
    if (isConnected) {
      synchronizationService.processQueue().then((_) {
        // Optionally refresh data after processing the queue
      });
    }
  }

  Response<T> _dioResponse<T>(result, Response<dynamic> response) {
    return Response<T>(
      data: result,
      statusCode: response.statusCode,
      statusMessage: response.statusMessage,
      headers: response.headers,
      requestOptions: response.requestOptions,
    );
  }
}
