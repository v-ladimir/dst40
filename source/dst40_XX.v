/******************************************************************************

  Модуль DST40 - объединяет в себе XX ядер (больше одного).
  
  ПРИМЕЧАНИЯ.
  
  1. Сигнал run_i формируется программно из HPS, следовательно он асинхронен
     по отношению к нашему модулю. Поэтому для исключения сбоев выполняется
     синхронизация этого сигнала с нашими тактами.

******************************************************************************/

module dst40_XX
#(
  parameter           NK   = 2,                                 // Количество хэширующих ядер в составе модуля
  parameter           L2NK = 1                                  // Логарифм по основанию 2 от количества ядер
)
(
  input               clock_i,                                  // Такты
  input        [39:0] challenge_i,                              // Запрос
  input        [23:0] response_i,                               // Ответ
  input        [39:0] start_key_i,                              // Стартовый ключ
  input               run_i,                                    // Разрешение поиска ключа
  output              key_found_o,                              // Флаг "ключ найден"
  output              key_not_found_o,                          // Флаг "работа закончена - ключ не найден"
  output     [NK-1:0] kernels_o,                                // Биты компараторов: 1 укажет на ядро, нашедшее ключ (или несколько 1 укажет на несколько ядер)
  output  [39-L2NK:0] key_o                                     // Результат поиска: младшие биты найденного ключа
);



//==============================================================//
// Внутренние провода/регистры
//==============================================================//

// Текущие рабочие регистры

reg   [40-L2NK:0] key_reg         = 0;                          // Перебираемые ключи
reg        [39:0] challenge_reg   = 0;                          // Текущий запрос
reg        [23:0] response_reg    = 0;                          // Текущий ответ
reg         [1:0] run_reg         = 0;                          // Регистр для синхронизации сигнала RUN с нашими тактами

reg         [6:0] tick_reg = 0;                                 // Номер текущего такта

// Результаты хэширования

wire     [NK-1:0] comparators_w;                                // Результаты работы ядер (валидны только начиная с такта 64)



//==============================================================//
// Комбинаторная схемотехника
//==============================================================//

wire    key_found_w     = ( tick_reg[6] && comparators_w != 0 );// Флаг "ключ найден": 1 если ключ найден

wire    key_not_found_w = key_reg[40-L2NK] & key_reg[6];        // Флаг "работа закончена - ключ не найден"

wire    run_w = run_reg[1] & ~key_found_o & ~key_not_found_o;   // Разрешение работы ядер

assign  key_found_o     = key_found_w;                          // Вывод флага "ключ найден" в порт key_found_o
assign  key_not_found_o = key_not_found_w;                      // Флаг "ключ не найден": 1 если все ключи перебраны и ключ не найден
assign  key_o           = key_reg[39-L2NK:0] - 40'd 64;         // Вывод в порт key_o младших бит найденного ключа
assign  kernels_o       = comparators_w;                        // Биты ядер, нашедших ключ



//--------------------------------------------------------------//
// Блок из XX ядер                                              //

genvar i;

generate

  for( i=0; i < NK; i=i+1 )
  begin: _kernels_

    KernelXX
    #(
      .NK             ( NK   ),                                 // Количество ядер
      .L2NK           ( L2NK ),                                 // Логарифм по основанию 2 от количества ядер
      .ADDRESS        ( i    )                                  // Номер ядра - фактически старшие биты ключа
    )
    KERNEL32_INST
    (
      .clock_i        ( clock_i            ),                   // Такты для конвеера
      .run_i          ( run_w              ),                   // Разрешение работы ядер
      .key_i          ( key_reg[39-L2NK:0] ),                   // Ключ
      .challenge_i    ( challenge_reg      ),                   // Запрос
      .response_i     ( response_reg       ),                   // Ожидаемый ответ
      .comparator_o   ( comparators_w[i]   )                    // Выход компаратора (1 - результат совпал с ожидаемым ответом)
    );

  end

endgenerate



//==============================================================//
// Синхронная схемотехника.
//==============================================================//

//--------------------------------------------------------------//
// Основной рабочий процесс - поиск ключа.

always @( posedge clock_i )
begin

  run_reg <= { run_reg[0], run_i };                             // Синхронизируем входной сигнал run_i с нашими тактами

  // Перебор ключей

  if( run_reg[1] )                                              // Выполняем поиск ключа пока разрешено.
  begin
    if( !tick_reg[6] )                                          // Инкрементируем номер такта, пока он не достигнет числа 64:
      tick_reg <= tick_reg + 1;                                 // начиная с этого момента выходные данные считаются валидными.

    if( !key_not_found_w && !key_found_w )                      // Выполняем работу по поиску только если перебраны не все ключи
      key_reg <= key_reg + 40'd 1;                              // и не найден подходящий ключ.
  end

  // Ожидание старта                                            // В режиме ожидания готовим схему к старту поиска

  else
  begin
    tick_reg      <= 0;                                         // Обнуляем номер такта (очищаем очередь конвеера)
    challenge_reg <= challenge_i;
    response_reg  <= response_i;
    key_reg       <= { 1'b 0, start_key_i[39-L2NK:0] };
  end
end


endmodule
