{*********************************************************}
{                                                         }
{                 Zeos Database Objects                   }
{                 ADO Statement Classes                   }
{                                                         }
{        Originally written by Janos Fegyverneki          }
{                                                         }
{*********************************************************}

{@********************************************************}
{    Copyright (c) 1999-2012 Zeos Development Group       }
{                                                         }
{ License Agreement:                                      }
{                                                         }
{ This library is distributed in the hope that it will be }
{ useful, but WITHOUT ANY WARRANTY; without even the      }
{ implied warranty of MERCHANTABILITY or FITNESS FOR      }
{ A PARTICULAR PURPOSE.  See the GNU Lesser General       }
{ Public License for more details.                        }
{                                                         }
{ The source code of the ZEOS Libraries and packages are  }
{ distributed under the Library GNU General Public        }
{ License (see the file COPYING / COPYING.ZEOS)           }
{ with the following  modification:                       }
{ As a special exception, the copyright holders of this   }
{ library give you permission to link this library with   }
{ independent modules to produce an executable,           }
{ regardless of the license terms of these independent    }
{ modules, and to copy and distribute the resulting       }
{ executable under terms of your choice, provided that    }
{ you also meet, for each linked independent module,      }
{ the terms and conditions of the license of that module. }
{ An independent module is a module which is not derived  }
{ from or based on this library. If you modify this       }
{ library, you may extend this exception to your version  }
{ of the library, but you are not obligated to do so.     }
{ If you do not wish to do so, delete this exception      }
{ statement from your version.                            }
{                                                         }
{                                                         }
{ The project web site is located on:                     }
{   http://zeos.firmos.at  (FORUM)                        }
{   http://sourceforge.net/p/zeoslib/tickets/ (BUGTRACKER)}
{   svn://svn.code.sf.net/p/zeoslib/code-0/trunk (SVN)    }
{                                                         }
{   http://www.sourceforge.net/projects/zeoslib.          }
{                                                         }
{                                                         }
{                                 Zeos Development Group. }
{********************************************************@}

unit ZDbcAdoStatement;

interface

{$I ZDbc.inc}

uses
  Types, Classes, SysUtils, ZCompatibility, ZClasses, ZSysUtils, ZCollections,
  ZDbcIntfs, ZPlainDriver, ZDbcStatement, ZDbcAdo, ZPlainAdoDriver, ZPlainAdo,
  ZVariant;

type
  {** Implements Generic ADO Statement. }
  TZAdoStatement = class(TZAbstractCallableStatement)
  protected
    AdoRecordSet: ZPlainAdo.RecordSet;
    FPlainDriver: IZPlainDriver;
    function GetCurrentResult(RC: Integer): Boolean; virtual;
    function IsSelect(const SQL: string): Boolean;
  public
    constructor Create(PlainDriver: IZPlainDriver; Connection: IZConnection; SQL: string; Info: TStrings);
    destructor Destroy; override;
    procedure Close; override;

    function ExecuteQuery(const SQL: string): IZResultSet; override;
    function ExecuteUpdate(const SQL: string): Integer; override;
    function Execute(const SQL: string): Boolean; override;
    function GetMoreResults: Boolean; override;
  end;

  {** Implements Prepared ADO Statement. }
  TZAdoPreparedStatement = class(TZAdoStatement)
  protected
    FAdoCommand: ZPlainAdo.Command;
    procedure SetInParamCount(NewParamCount: Integer); override;
    procedure InternalSetInParam(ParameterIndex: Integer; SQLType: TZSQLType;
      const Value: TZVariant; const ParamDirection: ParameterDirectionEnum);
    procedure SetInParam(ParameterIndex: Integer; SQLType: TZSQLType;
      const Value: TZVariant); override;
  public
    constructor Create(PlainDriver: IZPlainDriver; Connection: IZConnection; SQL: string; Info: TStrings);
    destructor Destroy; override;
    procedure Close; override;
    procedure ClearParameters; override;

    function ExecuteQueryPrepared: IZResultSet; override;
    function ExecuteUpdatePrepared: Integer; override;
    function ExecutePrepared: Boolean; override;
  end;

  {** Implements Prepared ADO Statement. }
  TZAdoCallableStatement = class(TZAdoPreparedStatement)
  protected
    function GetOutParam(ParameterIndex: Integer): TZVariant; override;
    procedure SetInParam(ParameterIndex: Integer; SQLType: TZSQLType;
      const Value: TZVariant); override;
  public
    constructor Create(PlainDriver: IZPlainDriver; Connection: IZConnection;
      SQL: string; Info: TStrings);
  end;

implementation

uses
{$IFNDEF FPC}
  Variants,
{$ENDIF}
  OleDB, ActiveX, ComObj,
  ZDbcLogging, ZDbcCachedResultSet, ZDbcResultSet,
  ZDbcAdoResultSet, ZDbcAdoUtils;

constructor TZAdoStatement.Create(PlainDriver: IZPlainDriver; Connection: IZConnection; SQL: string;
  Info: TStrings);
begin
  inherited Create(Connection, SQL, Info);
  FPlainDriver := PlainDriver;
end;

destructor TZAdoStatement.Destroy;
begin
  inherited;
end;

procedure TZAdoStatement.Close;
begin
  inherited;
  AdoRecordSet := nil;
end;

function TZAdoStatement.IsSelect(const SQL: string): Boolean;
begin
  Result := Uppercase(Copy(TrimLeft(Sql), 1, 6)) = 'SELECT';
end;

function TZAdoStatement.ExecuteQuery(const SQL: string): IZResultSet;
begin
  Result := nil;
  LastResultSet := nil;
  LastUpdateCount := -1;
  if not Execute(Sql) then
    while (not GetMoreResults) and (LastUpdateCount > -1) do ;
  Result := LastResultSet
end;

function TZAdoStatement.ExecuteUpdate(const SQL: string): Integer;
var
  RC: OleVariant;
begin
  try
    LastResultSet := nil;
    LastUpdateCount := -1;
    Self.SQL := sql;
    if IsSelect(SQL) then
    begin
      AdoRecordSet := CoRecordSet.Create;
      AdoRecordSet.MaxRecords := MaxRows;
      AdoRecordSet.Open(SQL, (Connection as IZAdoConnection).GetAdoConnection,
        adOpenStatic, adLockOptimistic, adAsyncFetch);
      GetCurrentResult(RC);
      AdoRecordSet.Close;
      AdoRecordSet := nil;
    end
    else
      AdoRecordSet := (Connection as IZAdoConnection).GetAdoConnection.Execute(SQL, RC, adExecuteNoRecords);
    Result := RC;
    LastUpdateCount := Result;
    DriverManager.LogMessage(lcExecute, FPlainDriver.GetProtocol, SQL);
  except
    on E: Exception do
    begin
      DriverManager.LogError(lcExecute, FPlainDriver.GetProtocol, SQL, 0, E.Message);
      raise;
    end;
  end

{  Result := -1;
  LastResultSet := nil;
  LastUpdateCount := -1;
  if Execute(Sql) then
    Result := LastUpdateCount;}
end;

function TZAdoStatement.Execute(const SQL: string): Boolean;
var
  RC: OleVariant;
begin
  try
    LastResultSet := nil;
    LastUpdateCount := -1;
    Self.SQL := sql;
    if IsSelect(SQL) then
    begin
      AdoRecordSet := CoRecordSet.Create;
      AdoRecordSet.MaxRecords := MaxRows;
      AdoRecordSet.Open(SQL, (Connection as IZAdoConnection).GetAdoConnection,
        adOpenStatic, adLockOptimistic, adAsyncFetch);
    end
    else
      AdoRecordSet := (Connection as IZAdoConnection).GetAdoConnection.Execute(SQL, RC, adExecuteNoRecords);
    Result := GetCurrentResult(RC);
    DriverManager.LogMessage(lcExecute, FPlainDriver.GetProtocol, SQL);
  except
    on E: Exception do
    begin
      DriverManager.LogError(lcExecute, FPlainDriver.GetProtocol, SQL, 0, E.Message);
      raise;
    end;
  end
end;

function TZAdoStatement.GetCurrentResult(RC: Integer): Boolean;
var
  NativeResultSet: IZResultSet;
begin
  Result := False;
  if Assigned(AdoRecordset) then
    if (AdoRecordSet.State and adStateOpen) = adStateOpen then
    begin
      Result := True;
      NativeResultSet := TZAdoResultSet.Create(Self, SQL, AdoRecordSet);
      if ResultSetConcurrency = rcUpdatable then
        LastResultSet := TZCachedResultSet.Create(NativeResultSet, SQL,
          TZAdoCachedResolver.Create((Connection as IZAdoConnection).GetAdoConnection,
          Self, NativeResultSet.GetMetaData), ConSettings)
      else LastResultSet := NativeResultSet;
    end;
  LastUpdateCount := RC;
end;

function TZAdoStatement.GetMoreResults: Boolean;
var
  RC: OleVariant;
begin
  Result := False;
  LastResultSet := nil;
  LastUpdateCount := -1;
  if Assigned(AdoRecordSet) then
  begin
    AdoRecordSet := AdoRecordSet.NextRecordset(RC);
    Result := GetCurrentResult(RC);
  end;
end;

constructor TZAdoPreparedStatement.Create(PlainDriver: IZPlainDriver;
  Connection: IZConnection; SQL: string; Info: TStrings);
begin
  FAdoCommand := CoCommand.Create;
  FAdoCommand.CommandText := SQL;
  inherited Create(PlainDriver, Connection, SQL, Info);
  FAdoCommand._Set_ActiveConnection((Connection as IZAdoConnection).GetAdoConnection);
  FAdoCommand.Prepared := True;
end;

destructor TZAdoPreparedStatement.Destroy;
begin
  inherited;
end;

procedure TZAdoPreparedStatement.Close;
begin
  inherited;
  FAdoCommand := nil;
end;

procedure TZAdoPreparedStatement.ClearParameters;
begin
end;

{**
  Sets a new parameter count and initializes the buffers.
  @param NewParamCount a new parameters count.
}
procedure TZAdoPreparedStatement.SetInParamCount(NewParamCount: Integer);
begin
  inherited;
  InParamCount := NewParamCount;
end;

{**
  Sets a variant value into specified parameter.
  @param ParameterIndex a index of the parameter.
  @param SqlType a parameter SQL type.
  @paran Value a new parameter value.
}
procedure TZAdoPreparedStatement.InternalSetInParam(ParameterIndex: Integer;
  SQLType: TZSQLType; const Value: TZVariant;
  const ParamDirection: ParameterDirectionEnum);
var
  S: Integer;
  HR: HResult;
  T: Integer;
  PC: Integer;
  P: ZPlainAdo.Parameter;
  B: IZBlob;
  V: OleVariant;
  OleDBCommand: IUnknown;
  OleDBCmdParams: ICommandWithParameters;
  OleDBCmdPrepare: ICommandPrepare;
  OleDBPC: NativeUInt;
  ParamInfo: PDBParamInfo;
  NamesBuffer: PPOleStr;
  RetValue: TZVariant;
begin
  PC := 0;
  if FAdoCommand.CommandType = adCmdStoredProc then
    try
      //some providers generates exceptions here mainly for update statements
      PC := FAdoCommand.Parameters.Count;
    except
    end
  else
  begin
    OleDBCommand := (FAdoCommand as ADOCommandConstruction).OLEDBCommand;
    OleDBCommand.QueryInterface(ICommandWithParameters, OleDBCmdParams);
    ParamInfo := nil;
    NamesBuffer := nil;
    if Assigned(OleDBCmdParams) then
    begin
      HR := OleDBCmdParams.GetParameterInfo(OleDBPC, ParamInfo, NamesBuffer);
//Access needs to be prepared for parameters
      if HR = DB_E_NOTPREPARED then
      begin
        OleDBCommand.QueryInterface(ICommandPrepare, OleDBCmdPrepare);
        if Assigned(OleDBCmdPrepare) then
        begin
          OleDBCmdPrepare.Prepare(0);
          OleDBCmdParams.GetParameterInfo(OleDBPC, ParamInfo, NamesBuffer);
        end
      end;
      if Assigned(ParamInfo) then ZAdoMalloc.Free(ParamInfo);
      if Assigned(NamesBuffer) then ZAdoMalloc.Free(NamesBuffer);
      PC := OleDBPC;
    end;
  end;

  RetValue:= Value;
  if (SQLType in [stAsciiStream, stUnicodeStream, stBinaryStream]) then
  begin
    B := DefVarManager.GetAsInterface(Value) as IZBlob;
    case SQLType of
      stAsciiStream:
        begin
          if Assigned(B) then
            DefVarManager.SetAsString(RetValue, String(B.GetString));
          SQLType := stString;
        end;
      stUnicodeStream:
        begin
          if Assigned(B) then
          begin
            if B.Connection = nil then
              B := TZAbstractBlob.CreateWithData(B.GetBuffer, B.Length, Self.GetConnection, B.WasDecoded);
            DefVarManager.SetAsUnicodeString(RetValue, B.GetUnicodeString);
          end;
          SQLType := stUnicodeString;
        end;
      stBinaryStream:
        begin
          if Assigned(B) then
            DefVarManager.SetAsBytes(RetValue, B.GetBytes);
          SQLType := stBytes;
        end;
    end;
  end;

  case RetValue.VType of
    vtNull: V := Null;
    vtBoolean: V := SoftVarManager.GetAsBoolean(RetValue);
    vtBytes: V := SoftVarManager.GetAsBytes(RetValue);
    vtInteger: V := Integer(SoftVarManager.GetAsInteger(RetValue));
    vtFloat: V := SoftVarManager.GetAsFloat(RetValue);
    vtString: V := SoftVarManager.GetAsString(RetValue);
    vtUnicodeString: V := WideString(SoftVarManager.GetAsUnicodeString(RetValue));
    vtDateTime: V := SoftVarManager.GetAsDateTime(RetValue);
  end;

  S := 0; //init val
  case SQLType of
    stString:
      begin
        S := Length(VarToStr(V));
        if S = 0 then S := 1;
        //V := Null; patch by zx - see http://zeos.firmos.at/viewtopic.php?t=1255
      end;
    stUnicodeString:
      begin
        S := Length(VarToWideStr(V))*2; //strange! Need size in bytes!!
        if S = 0 then S := 1;
        //V := Null; patch by zx - see http://zeos.firmos.at/viewtopic.php?t=1255
      end;
    stBytes:
      begin
        //V := StrToBytes(VarToStr(V));
        if (VarType(V) and varArray) <> 0 then
          S := VarArrayHighBound(V, 1) + 1;
        if S = 0 then V := Null;
      end;
  end;

  if VarIsNull(V) then
    T := ConvertSqlTypeToAdo(SQLType)
  else
    T := ConvertVariantToAdo(VarType(V));

  if ParameterIndex <= PC then
  begin

    P := FAdoCommand.Parameters.Item[ParameterIndex - 1];
    if not ( SQLType = stBytes ) then  //Variant varByte is not comparable with OleVariant -> exception
    begin
      if not VarIsNull(V) then
      begin
        P.Type_ := T;
        P.Size := S;
        // by aperger:
        // to use the new value at the next calling of the statement
        if {(P.Value = unassigned) or} (P.Value <> V) then
          P.Value := V;
      end;
    end
    else
      P.Value := V;
    FAdoCommand.Prepared:=false;
    p.Direction := ParamDirection;
  end
  else
  begin
    FAdoCommand.Parameters.Append(FAdoCommand.CreateParameter(
      'P' + IntToStr(ParameterIndex), T, ParamDirection, S, V));
  end;
end;

{**
  Sets a variant value into specified parameter.
  @param ParameterIndex a index of the parameter.
  @param SqlType a parameter SQL type.
  @paran Value a new parameter value.
}
procedure TZAdoPreparedStatement.SetInParam(ParameterIndex: Integer;
  SQLType: TZSQLType; const Value: TZVariant);
begin
  InternalSetInParam(ParameterIndex, SQLType, Value, adParamInput);
end;

{**
  Executes the SQL query in this <code>PreparedStatement</code> object
  and returns the result set generated by the query.

  @return a <code>ResultSet</code> object that contains the data produced by the
    query; never <code>null</code>
}
function TZAdoPreparedStatement.ExecuteQueryPrepared: IZResultSet;
begin
  if not ExecutePrepared then
    while (not GetMoreResults) and (LastUpdateCount > -1) do ;
  Result := LastResultSet;
end;

{**
  Executes the SQL INSERT, UPDATE or DELETE statement
  in this <code>PreparedStatement</code> object.
  In addition,
  SQL statements that return nothing, such as SQL DDL statements,
  can be executed.

  @return either the row count for INSERT, UPDATE or DELETE statements;
  or 0 for SQL statements that return nothing
}
function TZAdoPreparedStatement.ExecuteUpdatePrepared: Integer;
begin
  ExecutePrepared;
  Result := LastUpdateCount;
end;

{**
  Executes any kind of SQL statement.
  Some prepared statements return multiple results; the <code>execute</code>
  method handles these complex statements as well as the simpler
  form of statements handled by the methods <code>executeQuery</code>
  and <code>executeUpdate</code>.
  @see Statement#execute
}
function TZAdoPreparedStatement.ExecutePrepared: Boolean;
var
  RC: OleVariant;
begin
  LastResultSet := nil;
  LastUpdateCount := -1;

  try
    if IsSelect(SQL) then
    begin
      AdoRecordSet := CoRecordSet.Create;
      AdoRecordSet.MaxRecords := MaxRows;
      AdoRecordSet._Set_ActiveConnection(FAdoCommand.Get_ActiveConnection);
      AdoRecordSet.Open(FAdoCommand, EmptyParam, adOpenForwardOnly, adLockOptimistic, adAsyncFetch);
    end
    else
      AdoRecordSet := FAdoCommand.Execute(RC, EmptyParam, -1{, adExecuteNoRecords});
    //ClearInParameterValues;
    Result := GetCurrentResult(RC);
    DriverManager.LogMessage(lcExecute, FPlainDriver.GetProtocol, SQL);
  except
    on E: Exception do
    begin
      DriverManager.LogError(lcExecute, FPlainDriver.GetProtocol, SQL, 0, E.Message);
      raise;
    end;
  end
end;

{ TZAdoCallableStatement }
constructor TZAdoCallableStatement.Create(PlainDriver: IZPlainDriver;
  Connection: IZConnection; SQL: string; Info: TStrings);
begin
  inherited Create(PlainDriver, Connection, SQL, Info);
  FAdoCommand.CommandType := adCmdStoredProc;
end;

function TZAdoCallableStatement.GetOutParam(ParameterIndex: Integer): TZVariant;
var
  Temp: Variant;
  V: Variant;
  P: Pointer;
  TempBlob: IZBLob;
begin

  if ParameterIndex > OutParamCount then
    Result := NullVariant
  else
  begin
    Temp := FAdoCommand.Parameters.Item[ParameterIndex - 1].Value;

    case ConvertAdoToSqlType(FAdoCommand.Parameters.Item[ParameterIndex - 1].Type_,
      ConSettings.CPType) of
      stBoolean:
        DefVarManager.SetAsBoolean(Result, Temp);
      stByte, stShort, stInteger, stLong:
        DefVarManager.SetAsInteger(Result, Temp);
      stFloat, stDouble, stBigDecimal:
        DefVarManager.SetAsFloat(Result, Temp);
      stString, stAsciiStream:
        DefVarManager.SetAsString(Result, Temp);
      stUnicodeString, stUnicodeStream:
        DefVarManager.SetAsUnicodeString(Result, Temp);
      stBytes:
        DefVarManager.SetAsString(Result, String(BytesToStr(Temp)));
      stDate, stTime, stTimestamp:
        DefVarManager.SetAsDateTime(Result, Temp);
      stBinaryStream:
        begin
          if VarIsStr(V) then
          begin
            TempBlob := TZAbstractBlob.CreateWithStream(nil, GetConnection);
            TempBlob.SetString(AnsiString(V));
          end
          else
            if VarIsArray(V) then
            begin
              P := VarArrayLock(V);
              try
                TempBlob := TZAbstractBlob.CreateWithData(P, VarArrayHighBound(V, 1)+1, GetConnection);
              finally
                VarArrayUnLock(V);
              end;
            end;
          DefVarManager.SetAsInterface(Result, TempBlob);
          TempBlob := nil;
        end
      else
        DefVarManager.SetNull(Result);
    end;
    (*//!! Please fix.
    case VarType(Temp) of
      varString, varOleStr:
        DefVarManager.SetAsString(Result, Temp);
      varSmallInt, varInteger:
        DefVarManager.SetAsInteger(Result, Integer(Temp));
  {$IFNDEF FPC}
      varShortInt, varInt64:
        DefVarManager.SetAsInteger(Result, Temp);
  {$ENDIF}
      varDate:
        DefVarManager.SetAsDateTime(Result, Temp);
      varSingle, varDouble:
        DefVarManager.SetAsFloat(Result, Temp);
      else
        DefVarManager.SetNull(Result);
    end;*)
  end;

  LastWasNull := DefVarManager.IsNull(Result);
end;

procedure TZAdoCallableStatement.SetInParam(ParameterIndex: Integer;
  SQLType: TZSQLType; const Value: TZVariant);
begin
  case Self.FDBParamTypes[ParameterIndex-1] of
    0: //ptUnknown
      InternalSetInParam(ParameterIndex, SQLType, Value, adParamUnknown);
    1: //ptInput
      InternalSetInParam(ParameterIndex, SQLType, Value, adParamInput);
    2: //ptOut
      InternalSetInParam(ParameterIndex, SQLType, Value, adParamOutput);
    3: //ptInputOutput
      InternalSetInParam(ParameterIndex, SQLType, Value, adParamInputOutput);
    4: //ptResult
      InternalSetInParam(ParameterIndex, SQLType, Value, adParamReturnValue);
  end;
end;

end.

//  procedure RefreshFromOleDB;
//  var
//    I: Integer;
//    ParamCount: LongWord;
//    ParamInfo: PDBParamInfoArray;
//    NamesBuffer: PWideChar;
//    Name: WideString;
//    Parameter: _Parameter;
//    Direction: ParameterDirectionEnum;
//    OLEDBCommand: ICommand;
//    OLEDBParameters: ICommandWithParameters;
//    CommandPrepare: ICommandPrepare;
//    R: HResult;
//  begin
//    OLEDBCommand := (FAdoCommand as ADOCommandConstruction).OLEDBCommand as ICommand;
//    OLEDBCommand.QueryInterface(ICommandWithParameters, OLEDBParameters);
//    OLEDBParameters.SetParameterInfo(0, nil, nil);
//    if Assigned(OLEDBParameters) then
//    begin
//      ParamInfo := nil;
//      NamesBuffer := nil;
//      try
//        OLEDBCommand.QueryInterface(ICommandPrepare, CommandPrepare);
//        if Assigned(CommandPrepare) then R := CommandPrepare.Prepare(0);
//        R := OLEDBParameters.GetParameterInfo(ParamCount, PDBPARAMINFO(ParamInfo), @NamesBuffer);
//        if R = S_OK then
//          for I := 0 to ParamCount - 1 do
//            with ParamInfo[I] do
//            begin
//              { When no default name, fabricate one like ADO does }
//              if pwszName = nil then
//                Name := 'Param' + IntToStr(I+1) else { Do not localize }
//                Name := pwszName;
//              { ADO maps DBTYPE_BYTES to adVarBinary }
//              if wType = DBTYPE_BYTES then wType := adVarBinary;
//              { ADO maps DBTYPE_STR to adVarChar }
//              if wType = DBTYPE_STR then wType := adVarChar;
//              Direction := dwFlags and $F;
//              { Verify that the Direction is initialized }
//              if Direction = adParamUnknown then Direction := adParamInput;
//              Parameter := FAdoCommand.CreateParameter(Name, wType, Direction, ulParamSize, EmptyParam);
//              Parameter.Precision := bPrecision;
//              Parameter.NumericScale := ParamInfo[I].bScale;
//              Parameter.Attributes := dwFlags and $FFFFFFF0; { Mask out Input/Output flags }
//            end;
//      finally
//        if not Assigned(GlobalMalloc) then
//          OleCheck(CoGetMalloc(1, GlobalMalloc));
//        if (ParamInfo <> nil) then GlobalMalloc.Free(ParamInfo);
//        if (NamesBuffer <> nil) then GlobalMalloc.Free(NamesBuffer);
//      end;
//    end;
//  end;


